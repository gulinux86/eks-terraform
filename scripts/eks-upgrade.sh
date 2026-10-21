#!/usr/bin/env bash
# EKS upgrade steps, one subcommand each. Called by eks-upgrade-pr.yml and
# eks-upgrade.yml; every subcommand also runs by hand. ARCHITECTURE.md §13 has the
# design — why the order is what it is, and why nothing here runs `kubectl drain`.
#
#   bump <minor>                  rewrite the version + six add-on pins in hml and prod
#   preflight <env> [--advisory]  version skew, cluster status, EKS upgrade insights
#   compat <env> <minor> [--live]  every Helm-installed component supports <minor>
#   workloads [--strict]          PDBs that would block a drain; workloads that would blink
#   apply <env> <target>          plan -target -out, apply the saved plan if it has changes
#   nodes <selector> <minor> <s>  wait until every matching node runs <minor> and is Ready
#   verify <minor> <seconds>      nodes, Deployments, StatefulSets, Argo CD Applications
#
# Needs AWS credentials for bump/preflight/apply, and a kubeconfig for the rest.
set -euo pipefail

cd "$(dirname "$0")/.."

# The six add-on pins and the EKS add-on each one versions. Order is the order they
# are printed in.
ADDON_VARS=(vpc_cni_version coredns_version kube_proxy_version metrics_server_version ebs_csi_version pod_identity_agent_version)
declare -A ADDON_NAME=(
  [vpc_cni_version]=vpc-cni
  [coredns_version]=coredns
  [kube_proxy_version]=kube-proxy
  [metrics_server_version]=metrics-server
  [ebs_csi_version]=aws-ebs-csi-driver
  [pod_identity_agent_version]=eks-pod-identity-agent
)

die() { echo "::error::$*"; exit 1; }
warn() { echo "::warning::$*"; }
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$*" >>"$GITHUB_STEP_SUMMARY" || true; }

tfvars() { echo "foundation/environments/$1/terraform.tfvars"; }

# The value of `name = "value"` in a tfvars file.
tfvar() { sed -nE "s/^$2[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$1"; }

minor() { echo "${1#*.}"; } # "1.36" -> 36

# True when version $1 >= $2. sort -V orders v1.3.10-eksbuild.3 below v1.4.0-eksbuild.1.
version_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]; }

# --- bump ---------------------------------------------------------------------
# The rule in CLAUDE.md, "version bumps travel together", done by a script rather
# than by memory: kubernetes_version and all six pins, in both environments, in one
# change.
#
# Each pin moves to the version EKS marks as default for the target release — unless
# that is older than the pin already in use. EKS does not downgrade an add-on, and
# its default can trail what an environment runs (eks-pod-identity-agent: default
# v1.3.10 for 1.36 while hml ran v1.4.0), so the apply would fail after the control
# plane had moved. Then the current pin is kept if the target supports it; otherwise
# the newest compatible version above it; otherwise nothing is written.
cmd_bump() {
  local TARGET=${1:?usage: bump <kubernetes minor, e.g. 1.36>}
  [[ $TARGET =~ ^1\.[0-9]{2}$ ]] || die "target must look like 1.36, got '$TARGET'"

  local REGION
  REGION=$(tfvar "$(tfvars hml)" region)

  # EKS upgrades one minor at a time and never downgrades. Checked per file: prod
  # may legitimately trail hml by one.
  local ENV CURRENT TODO=()
  for ENV in hml prod; do
    CURRENT=$(tfvar "$(tfvars "$ENV")" kubernetes_version)
    if [ "$CURRENT" = "$TARGET" ]; then
      echo "$ENV is already on $TARGET; leaving it as it is"
    elif [ "$(minor "$TARGET")" -eq $(($(minor "$CURRENT") + 1)) ]; then
      TODO+=("$ENV")
    else
      die "$ENV is on $CURRENT; EKS moves one minor at a time, so the next step is 1.$(($(minor "$CURRENT") + 1)), not $TARGET"
    fi
  done
  [ ${#TODO[@]} -gt 0 ] || { echo "nothing to bump"; return 0; }

  # Fails early, and by name, when the release does not exist in EKS yet.
  local STATUS
  STATUS=$(aws eks describe-cluster-versions --region "$REGION" --cluster-versions "$TARGET" \
    --query 'clusterVersions[0].versionStatus' --output text 2>/dev/null || true)
  case "$STATUS" in
    STANDARD_SUPPORT | EXTENDED_SUPPORT) echo "EKS $TARGET: $STATUS" ;;
    "" | None) die "EKS does not offer Kubernetes $TARGET in $REGION (yet)" ;;
    *) warn "EKS $TARGET status is $STATUS" ;;
  esac

  # Resolve every pin, for every environment, before touching a file, so a missing
  # or impossible add-on leaves the tree unchanged rather than half-bumped.
  local VAR NAME JSON DEFAULT COMPAT OLD V NOTE
  declare -A NEW WHY
  for VAR in "${ADDON_VARS[@]}"; do
    NAME=${ADDON_NAME[$VAR]}
    JSON=$(aws eks describe-addon-versions --region "$REGION" --addon-name "$NAME" \
      --kubernetes-version "$TARGET" --output json)
    DEFAULT=$(jq -r --arg k "$TARGET" '[.addons[0].addonVersions[]?
      | select(any(.compatibilities[]; .clusterVersion == $k and .defaultVersion))
      | .addonVersion][0] // empty' <<<"$JSON")
    # Every version that lists the target release, newest first.
    COMPAT=$(jq -r --arg k "$TARGET" '.addons[0].addonVersions[]?
      | select(any(.compatibilities[]; .clusterVersion == $k)) | .addonVersion' <<<"$JSON" | sort -rV)
    [ -n "$COMPAT" ] || die "no $NAME build is published for Kubernetes $TARGET"
    [ -n "$DEFAULT" ] || DEFAULT=$(head -1 <<<"$COMPAT")

    for ENV in "${TODO[@]}"; do
      OLD=$(tfvar "$(tfvars "$ENV")" "$VAR")
      [ -n "$OLD" ] || die "$(tfvars "$ENV") has no $VAR line to rewrite"
      if version_ge "$DEFAULT" "$OLD"; then
        V=$DEFAULT NOTE=""
      elif grep -qxF "$OLD" <<<"$COMPAT"; then
        V=$OLD NOTE="kept — EKS default $DEFAULT is older"
      else
        V=$(head -1 <<<"$COMPAT")
        version_ge "$V" "$OLD" \
          || die "$NAME $OLD ($ENV) has no successor for $TARGET: the newest compatible is $V, and EKS does not downgrade add-ons"
        NOTE="newest compatible — EKS default $DEFAULT is older"
      fi
      NEW[$ENV:$VAR]=$V
      WHY[$ENV:$VAR]=$NOTE
    done
  done

  summary "### EKS $TARGET — version pins"
  summary ""
  summary "| Variable | Old | New | Note |"
  summary "|---|---|---|---|"
  local FILE
  for ENV in "${TODO[@]}"; do
    FILE=$(tfvars "$ENV")
    echo "== $FILE"
    for VAR in kubernetes_version "${ADDON_VARS[@]}"; do
      if [ "$VAR" = kubernetes_version ]; then V=$TARGET NOTE=""; else V=${NEW[$ENV:$VAR]} NOTE=${WHY[$ENV:$VAR]}; fi
      OLD=$(tfvar "$FILE" "$VAR")
      [ -n "$OLD" ] || die "$FILE has no $VAR line to rewrite"
      sed -i -E "s/^(${VAR}[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\1\"$V\"/" "$FILE"
      [ "$(tfvar "$FILE" "$VAR")" = "$V" ] || die "failed to rewrite $VAR in $FILE"
      printf '  %-28s %-24s -> %-24s %s\n' "$VAR" "$OLD" "$V" "$NOTE"
      summary "| \`$ENV\` $VAR | $OLD | **$V** | $NOTE |"
    done
  done

  # The bastion's kubectl is a module default, not a pin. It may trail the API
  # server by one minor; past that, `kubectl` on the bastion starts failing.
  local KUBECTL
  KUBECTL=$(sed -n '/variable "kubectl_version"/,/^}/s/.*default[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' foundation/modules/bastion/variables.tf)
  KUBECTL=${KUBECTL%.*} # 1.35.0 -> 1.35
  if [ "$(minor "$TARGET")" -gt $(($(minor "$KUBECTL") + 1)) ]; then
    warn "bastion kubectl $KUBECTL is more than one minor behind $TARGET — bump kubectl_version in foundation/modules/bastion/variables.tf"
  fi
}

# --- preflight ----------------------------------------------------------------
# Ends with REGION=, CLUSTER= and TARGET= lines; the workflow copies those (and only
# those) into $GITHUB_ENV.
#
# --advisory (eks-upgrade-pr): a cluster that is not running is a notice, not an
# error. hml is destroyed between sessions, so there that is the normal case.
cmd_preflight() {
  local ENV=${1:?usage: preflight <env> [--advisory]} ADVISORY=${2:-}
  local FILE REGION TARGET CLUSTER
  FILE=$(tfvars "$ENV")
  REGION=$(tfvar "$FILE" region)
  TARGET=$(tfvar "$FILE" kubernetes_version)
  CLUSTER="$(tfvar "$FILE" project_name)-cluster"

  local DESC STATUS CURRENT
  if ! DESC=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" --output json 2>/dev/null); then
    if [ "$ADVISORY" = --advisory ]; then
      echo "::notice::$CLUSTER is not running; no upgrade insights to read. eks-upgrade reads them before changing anything."
      return 0
    fi
    die "no cluster $CLUSTER in $REGION — run terraform-deploy for a new cluster; this workflow upgrades a live one"
  fi
  STATUS=$(jq -r .cluster.status <<<"$DESC")
  CURRENT=$(jq -r .cluster.version <<<"$DESC")
  [ "$STATUS" = ACTIVE ] || die "cluster is $STATUS, not ACTIVE — another update may be in progress"

  echo "cluster $CLUSTER: $CURRENT, tfvars: $TARGET"
  if [ "$CURRENT" = "$TARGET" ]; then
    # Not an error: this is how a run that stopped after the control plane resumes.
    echo "control plane already on $TARGET; the remaining phases still run"
  elif [ "$(minor "$TARGET")" -ne $(($(minor "$CURRENT") + 1)) ]; then
    die "cluster is on $CURRENT and tfvars ask for $TARGET — EKS moves one minor at a time"
  else
    # Upgrade insights: EKS's own scan for APIs removed in the target release and
    # for add-ons or nodes it cannot carry across. ERROR blocks; WARNING is shown.
    local INSIGHTS
    INSIGHTS=$(aws eks list-insights --region "$REGION" --cluster-name "$CLUSTER" --output json \
      --filter "{\"categories\":[\"UPGRADE_READINESS\"],\"kubernetesVersions\":[\"$TARGET\"]}")
    jq -r '.insights[] | "  \(.insightStatus.status)\t\(.name)"' <<<"$INSIGHTS"
    jq -r '.insights[] | select(.insightStatus.status == "WARNING") | "::warning::insight: \(.name) — \(.insightStatus.reason)"' <<<"$INSIGHTS"
    if jq -e '[.insights[] | select(.insightStatus.status == "ERROR")] | length > 0' <<<"$INSIGHTS" >/dev/null; then
      jq -r '.insights[] | select(.insightStatus.status == "ERROR") | "::error::insight: \(.name) — \(.insightStatus.reason)"' <<<"$INSIGHTS"
      die "EKS upgrade insights report errors for $TARGET (aws eks describe-insight for detail)"
    fi
  fi

  echo "REGION=$REGION"
  echo "CLUSTER=$CLUSTER"
  echo "TARGET=$TARGET"
}

# --- compat -------------------------------------------------------------------
# Does every component installed on top of EKS support the target minor?
#
# The six EKS add-ons need no check here: `bump` only picks versions EKS lists as
# compatible. Everything Helm installs is different — Argo CD Applications in the
# platform repository, and helm_release resources in the workload layer — and its
# own Chart.yaml does not answer the question: `kubeVersion` is a floor where it is
# set at all (cert-manager ">= 1.22", Istio and Karpenter nothing), never a ceiling.
#
# So each project's own compatibility matrix is read, at run time, from the file its
# documentation is generated from. A copy here would be one more version list to
# forget. Every read fails closed: an unreachable matrix blocks, as does a version
# the matrix does not list (cert-manager drops releases once they are out of support).
#
#   Karpenter      compatibility.yaml             aws/karpenter-provider-aws
#   Istio          supportStatus.yml              istio/istio.io
#   cert-manager   supported-releases table       cert-manager/website
#   Argo CD        tested-kubernetes-versions.md  argoproj/argo-cd, per release branch
#
# Anything else is reported as unverified, not passed: no published matrix means
# nobody has said. EKS upgrade insights (preflight) still catch the failure that
# matters most for those — an API removed in the target release that they use.
#
# Components are discovered, not listed: a new Application or helm_release is
# checked, or reported unverified, without editing this script.
KARPENTER_MATRIX=https://raw.githubusercontent.com/aws/karpenter-provider-aws/main/hack/docs/compatibilitymatrix_gen/compatibility.yaml
ISTIO_MATRIX=https://raw.githubusercontent.com/istio/istio.io/master/data/compatibility/supportStatus.yml
CERT_MANAGER_MATRIX=https://raw.githubusercontent.com/cert-manager/website/master/content/docs/releases/README.md

fetch() { curl -sSfL --retry 3 --max-time 30 "$1"; }
mm() { local v=${1#v}; cut -d. -f1,2 <<<"$v"; } # v1.21.1 -> 1.21

# "repoURL|chart|targetRevision" per external source of every Application under $1.
# Sources pointing back at the platform repository itself are its own manifests.
app_sources() {
  local SELF=$2
  # shellcheck disable=SC2016 # $NF and $2 are awk's fields, not shell expansions
  find "$1" -name '*.yaml' -print0 | xargs -0 -r awk -v self="$SELF" '
    function emit() { if (url != "" && url != self) print url "|" chart "|" rev; url = chart = rev = "" }
    FNR == 1 { emit() }
    /^[[:space:]]*-?[[:space:]]*repoURL:/ { emit(); url = $NF }
    /^[[:space:]]*chart:/ { chart = $2 }
    /^[[:space:]]*targetRevision:/ { rev = $2 }
    END { emit() }' | tr -d '"'"'" | sort -u
}

# "repository|chart|version" per helm_release in the workload layer that pulls from
# a repository (local charts have none). A version given as var.X is followed the
# way Terraform would: the module block in workload/main.tf whose source is that
# directory passes X = var.Y, and Y is set in the environment's tfvars.
tf_releases() {
  local ENV=$1 F MOD REPO CHART VER ROOT
  for F in workload/modules/*/*.tf; do
    MOD=$(basename "$(dirname "$F")")
    awk '/resource "helm_release"/ { r = 1; repo = chart = ver = "" }
         r && /^[[:space:]]*repository[[:space:]]*=/ { repo = $3 }
         r && /^[[:space:]]*chart[[:space:]]*=/ { chart = $3 }
         r && /^[[:space:]]*version[[:space:]]*=/ { ver = $3 }
         r && /^}/ { if (repo != "") print repo "|" chart "|" ver; r = 0 }' "$F" \
      | tr -d '"' | while IFS='|' read -r REPO CHART VER; do
        if [[ $VER == var.* ]]; then
          ROOT=$(awk -v src="./modules/$MOD" -v arg="${VER#var.}" '
            /^module "/ { m = 0 }
            $1 == "source" && $3 == "\"" src "\"" { m = 1 }
            m && $1 == arg && $3 ~ /^var\./ { sub(/^var\./, "", $3); print $3; exit }' workload/main.tf)
          VER=$([ -n "$ROOT" ] && tfvar "workload/environments/$ENV/terraform.tfvars" "$ROOT")
        fi
        echo "$REPO|$CHART|${VER:-unresolved}"
      done
  done
}

# Each check prints "ok <detail>", "no <detail>", or "unknown <detail>".
check_karpenter() {
  local MATRIX RANGE MIN MAX
  MATRIX=$(fetch "$KARPENTER_MATRIX") || { echo "unknown matrix unreachable"; return; }
  RANGE=$(awk -v app="$(mm "$1").x" '
    { gsub(/"/, "") }
    $2 == "appVersion:" { a = $3 } $1 == "appVersion:" { a = $2 }
    $1 == "minK8sVersion:" { mn = $2 }
    $1 == "maxK8sVersion:" { mx = $2; if (a == app) r = mn " " mx }
    END { print r }' <<<"$MATRIX")
  [ -n "$RANGE" ] || { echo "unknown $(mm "$1").x is not in the matrix"; return; }
  read -r MIN MAX <<<"$RANGE"
  in_range "$2" "$MIN" "$MAX" && echo "ok supports $MIN–$MAX" || echo "no supports $MIN–$MAX"
}

check_istio() {
  local MATRIX LIST
  MATRIX=$(fetch "$ISTIO_MATRIX") || { echo "unknown matrix unreachable"; return; }
  LIST=$(awk -v v="\"$(mm "$1")\"" '$2 == "version:" { f = ($3 == v) } f && $1 == "k8sVersions:" { $1 = ""; print; exit }' <<<"$MATRIX" | tr -d ' "[]')
  [ -n "$LIST" ] || { echo "unknown $(mm "$1") is not in the matrix"; return; }
  grep -qx "$2" <<<"${LIST//,/$'\n'}" && echo "ok supports ${LIST//,/, }" || echo "no supports ${LIST//,/, }"
}

check_cert_manager() {
  local MATRIX COL MIN MAX
  MATRIX=$(fetch "$CERT_MANAGER_MATRIX") || { echo "unknown matrix unreachable"; return; }
  # | [1.21][] | Jul 08, 2026 | Release of 1.23 | 1.33 → 1.36 / 4.20 → 4.22 | ...
  COL=$(awk -F'|' -v r="[$(mm "$1")][]" '{ gsub(/ /, "", $2) } $2 == r { print $5; exit }' <<<"$MATRIX")
  read -r MIN _ MAX _ <<<"${COL%%/*}"
  [ -n "$MAX" ] || { echo "unknown $(mm "$1") is not a supported release"; return; }
  in_range "$2" "$MIN" "$MAX" && echo "ok supports $MIN–$MAX" || echo "no supports $MIN–$MAX"
}

check_argocd() {
  # The chart's version is not Argo CD's; the matrix is keyed by the latter.
  local APP LINE
  APP=$(fetch "https://raw.githubusercontent.com/argoproj/argo-helm/argo-cd-$1/charts/argo-cd/Chart.yaml" \
    | sed -nE 's/^appVersion:[[:space:]]*"?([^"]+)"?.*/\1/p') || true
  [ -n "$APP" ] || { echo "unknown could not read the chart's appVersion"; return; }
  LINE=$(fetch "https://raw.githubusercontent.com/argoproj/argo-cd/release-$(mm "$APP")/docs/operator-manual/tested-kubernetes-versions.md" \
    | grep -E "^\| *$(mm "$APP") *\|") || true
  [ -n "$LINE" ] || { echo "unknown Argo CD $(mm "$APP") is not in the matrix"; return; }
  local TESTED
  TESTED=$(cut -d'|' -f3 <<<"$LINE" | xargs)
  grep -q "v$2\b" <<<"$TESTED" && echo "ok Argo CD $APP tested on $TESTED" || echo "no Argo CD $APP tested on $TESTED"
}

in_range() { [ "$(minor "$1")" -ge "$(minor "$2")" ] && [ "$(minor "$1")" -le "$(minor "$3")" ]; }

cmd_compat() {
  local ENV=${1:?usage: compat <env> <minor> [--live]} TARGET=${2:?usage: compat <env> <minor> [--live]} LIVE=${3:-}

  # With a live cluster, what runs must be what is declared — otherwise checking
  # the declared versions says nothing about the running ones.
  if [ "$LIVE" = --live ] && kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    local DRIFT
    DRIFT=$(kubectl get applications -A -o json | jq -r '.items[]
      | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
      | "\(.metadata.name) \(.status.sync.status)/\(.status.health.status)"')
    [ -z "$DRIFT" ] || die "Applications not Synced/Healthy, so the running versions are not the declared ones: $(tr '\n' ' ' <<<"$DRIFT")"
  fi

  local WTF REPO REV DIR
  WTF=workload/environments/$ENV/terraform.tfvars
  REPO=$(tfvar "$WTF" platform_repo_url)
  REV=$(tfvar "$WTF" platform_repo_revision)
  DIR=$(mktemp -d)
  git clone -q --depth 1 --branch "$REV" "$REPO" "$DIR" 2>/dev/null \
    || die "could not clone $REPO at $REV to read the declared component versions"

  local COMPONENTS
  COMPONENTS=$({ app_sources "$DIR" "$REPO" | sed 's/^/argo|/'; tf_releases "$ENV" | sed 's/^/terraform|/'; })
  rm -rf "$DIR"

  summary "### Components on Kubernetes $TARGET"
  summary ""
  summary "| Component | Version | Installed by | Result |"
  summary "|---|---|---|---|"

  local BY URL CHART VER NAME R STATUS DETAIL BAD=0 UNVERIFIED=() SEEN_ISTIO=""
  while IFS='|' read -r BY URL CHART VER; do
    NAME=${CHART:-$(basename "$URL")}
    case "$URL|$NAME" in
      *karpenter*) R=$(check_karpenter "$VER" "$TARGET") ;;
      *istio-release*)
        # base, istiod, cni and ztunnel are one Istio release; check it once.
        [ "$SEEN_ISTIO" = "$VER" ] && continue
        SEEN_ISTIO=$VER NAME="istio (base, istiod, cni, ztunnel)"
        R=$(check_istio "$VER" "$TARGET") ;;
      *\|cert-manager) R=$(check_cert_manager "$VER" "$TARGET") ;;
      *\|argo-cd) R=$(check_argocd "$VER" "$TARGET") ;;
      *) R="unverified no published Kubernetes compatibility matrix" ;;
    esac
    STATUS=${R%% *} DETAIL=${R#* }
    case "$STATUS" in
      ok) echo "ok          $NAME $VER — $DETAIL"; summary "| $NAME | \`$VER\` | $BY | ✅ $DETAIL |" ;;
      unverified) echo "unverified  $NAME $VER"; summary "| $NAME | \`$VER\` | $BY | ⚠️ $DETAIL |"; UNVERIFIED+=("$NAME $VER") ;;
      no) echo "::error::$NAME $VER does not support Kubernetes $TARGET — $DETAIL"
          summary "| $NAME | \`$VER\` | $BY | ❌ $DETAIL |"; BAD=1 ;;
      *) echo "::error::cannot verify $NAME $VER against Kubernetes $TARGET — $DETAIL"
         summary "| $NAME | \`$VER\` | $BY | ❌ could not verify: $DETAIL |"; BAD=1 ;;
    esac
  done <<<"$COMPONENTS"

  if [ ${#UNVERIFIED[@]} -gt 0 ]; then
    warn "no published Kubernetes matrix, check release notes by hand: ${UNVERIFIED[*]}"
  fi
  [ "$BAD" -eq 0 ] || die "resolve the components above first — upgrade what does not support $TARGET (platform repository or workload layer) and let it roll out; a component that could not be verified blocks too, then rerun"
}

# --- workloads ----------------------------------------------------------------
# What a node roll will do to what runs on the cluster. Read-only.
#
# Blocks: a PDB that currently allows zero disruptions. Every drain of a node
# holding one of its pods waits on it — EKS gives up after 15 minutes and fails the
# node group update; Karpenter waits indefinitely.
#
# Warns (blocks with --strict): a single replica, which is down from eviction until
# its replacement is Ready; and several replicas with no PDB, which one drain may
# evict together.
cmd_workloads() {
  local STRICT=${1:-}
  local PDBS WL
  PDBS=$(kubectl get pdb -A -o json)
  WL=$(kubectl get deploy,statefulset -A -o json)

  local BLOCKING
  BLOCKING=$(jq -r '.items[]
    | select((.status.expectedPods // 0) > 0 and (.status.disruptionsAllowed // 0) == 0)
    | "\(.metadata.namespace)/\(.metadata.name) (expected \(.status.expectedPods), healthy \(.status.currentHealthy // 0))"' <<<"$PDBS")

  # A PDB covers a workload when its matchLabels are a subset of the pod template's
  # labels. A selector using matchExpressions is counted as covering: evaluating it
  # here would be a reimplementation, and the cost of being wrong is one warning.
  local FINDINGS
  FINDINGS=$(jq -r --argjson pdbs "$PDBS" '
    .items[]
    | select((.spec.replicas // 1) > 0)
    | . as $w
    | ($w.spec.template.metadata.labels // {}) as $labels
    | ([$pdbs.items[]
        | select(.metadata.namespace == $w.metadata.namespace)
        | .spec.selector as $s
        | select(($s.matchExpressions // []) != []
                 or (($s.matchLabels // {}) != {} and ($s.matchLabels | to_entries | all(. as $e | $labels[$e.key] == $e.value))))
      ] | length > 0) as $covered
    | "\($w.kind)/\($w.metadata.namespace)/\($w.metadata.name)" as $id
    | if ($w.spec.replicas // 1) < 2 then "single\t\($id)"
      elif ($covered | not) then "nopdb\t\($id) (\($w.spec.replicas) replicas)"
      else empty end' <<<"$WL")

  # karpenter.sh/do-not-disrupt pins a pod's node: drift skips it until the pod goes.
  local PINNED
  PINNED=$(kubectl get pods -A -o json | jq -r '.items[]
    | select(.metadata.annotations["karpenter.sh/do-not-disrupt"] == "true")
    | "\(.metadata.namespace)/\(.metadata.name) on \(.spec.nodeName)"')

  local N_SINGLE N_NOPDB
  N_SINGLE=$(grep -c '^single' <<<"$FINDINGS" || true)
  N_NOPDB=$(grep -c '^nopdb' <<<"$FINDINGS" || true)

  summary "### Workload readiness"
  summary ""
  if [ -n "$BLOCKING" ]; then
    summary ""; summary "**Blocking — PDBs allowing no disruption:**"
    while read -r L; do echo "::error::PDB allows no disruption, a drain will hang on it: $L"; summary "- \`$L\`"; done <<<"$BLOCKING"
  fi
  if [ "$N_SINGLE" -gt 0 ]; then
    summary ""; summary "**Single replica — unavailable while its node drains ($N_SINGLE):**"
    grep '^single' <<<"$FINDINGS" | cut -f2- | while read -r L; do warn "single replica: $L"; summary "- \`$L\`"; done
  fi
  if [ "$N_NOPDB" -gt 0 ]; then
    summary ""; summary "**Several replicas, no PDB — one drain may evict them together ($N_NOPDB):**"
    grep '^nopdb' <<<"$FINDINGS" | cut -f2- | while read -r L; do warn "no PDB: $L"; summary "- \`$L\`"; done
  fi
  if [ -n "$PINNED" ]; then
    summary ""; summary "**\`karpenter.sh/do-not-disrupt\` — the node waits for the pod:**"
    while read -r L; do warn "do-not-disrupt: $L"; summary "- \`$L\`"; done <<<"$PINNED"
  fi
  [ -z "$BLOCKING$FINDINGS$PINNED" ] && summary "Every workload has 2+ replicas and a PDB that allows a disruption."

  [ -z "$BLOCKING" ] || die "fix or delete the PDBs above before upgrading"
  if [ "$STRICT" = --strict ] && [ $((N_SINGLE + N_NOPDB)) -gt 0 ]; then
    die "strict mode: $N_SINGLE single-replica and $N_NOPDB unprotected workloads would be disrupted"
  fi
  echo "workloads: $N_SINGLE single-replica, $N_NOPDB without a PDB — see warnings"
}

# --- apply --------------------------------------------------------------------
# One phase = one targeted, saved plan. -detailed-exitcode tells "nothing to do"
# (0) from "changes" (2), so a resumed run skips phases already done instead of
# applying an empty plan.
cmd_apply() {
  local ENV=${1:?usage: apply <env> <target address>} TARGET=${2:?usage: apply <env> <target address>}
  local RC=0
  terraform -chdir=foundation plan -input=false -detailed-exitcode -out=tfplan \
    -target="$TARGET" -var-file="environments/$ENV/terraform.tfvars" || RC=$?
  case $RC in
    0) echo "$TARGET: no changes" ;;
    2) terraform -chdir=foundation apply -input=false -auto-approve tfplan ;;
    *) die "plan for $TARGET failed" ;;
  esac
}

# --- nodes --------------------------------------------------------------------
# Waits; does not act. The node group's roll is done by EKS and Karpenter's by its
# drift controller — both already surge, cordon, drain against PDBs and terminate.
# A `kubectl drain` from here would race them.
cmd_nodes() {
  local SEL=${1:?usage: nodes <label selector> <minor> <timeout s>} TARGET=${2:?} TIMEOUT=${3:?}
  local DEADLINE=$((SECONDS + TIMEOUT)) NODES TOTAL DONE
  while :; do
    NODES=$(kubectl get nodes -l "$SEL" -o json)
    TOTAL=$(jq '.items | length' <<<"$NODES")
    if [ "$TOTAL" -eq 0 ]; then
      echo "no nodes match $SEL; nothing to wait for"
      return 0
    fi
    DONE=$(jq --arg v "v$TARGET." '[.items[]
      | select(.status.nodeInfo.kubeletVersion | startswith($v))
      | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))
      | select(.spec.unschedulable | not)] | length' <<<"$NODES")
    echo "$(date +%T) $SEL: $DONE/$TOTAL on $TARGET and Ready"
    [ "$DONE" -eq "$TOTAL" ] && return 0
    if [ $SECONDS -ge $DEADLINE ]; then
      jq -r '.items[] | "  \(.metadata.name)\t\(.status.nodeInfo.kubeletVersion)\tunschedulable=\(.spec.unschedulable // false)"' <<<"$NODES"
      die "$SEL did not converge on $TARGET within ${TIMEOUT}s"
    fi
    sleep 30
  done
}

# --- verify -------------------------------------------------------------------
# The upgrade is done when the cluster looks the way it did before it, one minor up.
cmd_verify() {
  local TARGET=${1:?usage: verify <minor> <timeout s>} TIMEOUT=${2:?}
  local DEADLINE=$((SECONDS + TIMEOUT)) BAD
  while :; do
    BAD=$(
      kubectl get nodes -o json | jq -r --arg v "v$TARGET." '.items[]
        | select((.status.nodeInfo.kubeletVersion | startswith($v) | not)
                 or (any(.status.conditions[]; .type == "Ready" and .status == "True") | not)
                 or .spec.unschedulable)
        | "node \(.metadata.name) \(.status.nodeInfo.kubeletVersion)"'
      kubectl get deploy -A -o json | jq -r '.items[]
        | select((.status.availableReplicas // 0) < (.spec.replicas // 1)
                 or (.status.updatedReplicas // 0) < (.spec.replicas // 1))
        | "deployment \(.metadata.namespace)/\(.metadata.name) \(.status.availableReplicas // 0)/\(.spec.replicas // 1) available"'
      kubectl get statefulset -A -o json | jq -r '.items[]
        | select((.status.readyReplicas // 0) < (.spec.replicas // 1))
        | "statefulset \(.metadata.namespace)/\(.metadata.name) \(.status.readyReplicas // 0)/\(.spec.replicas // 1) ready"'
      if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
        kubectl get applications -A -o json | jq -r '.items[]
          | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
          | "application \(.metadata.name) \(.status.sync.status)/\(.status.health.status)"'
      fi
    )
    if [ -z "$BAD" ]; then
      echo "every node on $TARGET and Ready; every Deployment, StatefulSet and Application healthy"
      summary "### Verified"
      summary ""
      summary "Every node on $TARGET and Ready; every Deployment, StatefulSet and Argo CD Application healthy."
      return 0
    fi
    if [ $SECONDS -ge $DEADLINE ]; then
      while read -r L; do echo "::error::$L"; done <<<"$BAD"
      die "cluster did not settle within ${TIMEOUT}s"
    fi
    echo "$(date +%T) waiting on $(wc -l <<<"$BAD") item(s), e.g. $(head -1 <<<"$BAD")"
    sleep 30
  done
}

CMD=${1:-}
shift || true
case "$CMD" in
  bump) cmd_bump "$@" ;;
  preflight) cmd_preflight "$@" ;;
  compat) cmd_compat "$@" ;;
  workloads) cmd_workloads "$@" ;;
  apply) cmd_apply "$@" ;;
  nodes) cmd_nodes "$@" ;;
  verify) cmd_verify "$@" ;;
  *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

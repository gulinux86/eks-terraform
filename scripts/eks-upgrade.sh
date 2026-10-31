#!/usr/bin/env bash
# EKS upgrade steps, one subcommand each. Called by eks-upgrade-pr.yml and
# eks-upgrade.yml; every subcommand also runs by hand. ARCHITECTURE.md §13 has the
# design — why the order is what it is, and why nothing here runs `kubectl drain`.
#
#   bump <minor>                  rewrite the version + six add-on pins in hml and prod
#   preflight <env> [--advisory]  version skew, cluster status, EKS upgrade insights
#   compat <env> <minor> [--live]  every Helm-installed component supports <minor>
#   workloads [--strict]          PDBs that would block a drain; workloads that would blink
#   platform [--settle]           the traffic path is highly available — blocks if not
#   karpenter hold|release        keep Karpenter's nodes in place until the last phase
#   ami <minor> <seconds>         wait until Karpenter's NodeClasses resolve a <minor> image
#   probe start|report <env> ...  requests through the ingress ALB, from the bastion
#   apply <env> <target>          plan -target -out, apply the saved plan if it has changes
#   nodes <selector> <minor> <s>  wait until every matching node runs <minor> and is Ready
#   health <env> <seconds>        between phases: nodes, data plane, traffic path, probe
#   verify <minor> <seconds>      nodes, Deployments, StatefulSets, Argo CD Applications
#
# Needs AWS credentials for bump/preflight/apply/probe, and a kubeconfig for the rest.
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
    # None at all is not "none failed". EKS scans a new cluster some time after it is
    # created — a fresh hml had none half an hour in — and an empty list would pass
    # the ERROR check below without anything having been checked.
    if jq -e '.insights | length == 0' <<<"$INSIGHTS" >/dev/null; then
      warn "EKS has not scanned $CLUSTER for $TARGET yet: no upgrade insights were checked. A cluster created recently gets them later; rerun to have them read."
    fi
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

  local WTF REPO REV DIR APPS
  WTF=workload/environments/$ENV/terraform.tfvars
  REPO=$(tfvar "$WTF" platform_repo_url)
  REV=$(tfvar "$WTF" platform_repo_revision)
  APPS=$(tfvar "$WTF" apps_repo_url)
  DIR=$(mktemp -d)
  git clone -q --depth 1 --branch "$REV" "$REPO" "$DIR" 2>/dev/null \
    || die "could not clone $REPO at $REV to read the declared component versions"

  local COMPONENTS
  # Applications pointing at the apps repository are workloads, not components:
  # they publish no matrix to check, and the `workloads` step covers them.
  COMPONENTS=$({ app_sources "$DIR" "$REPO" | awk -F'|' -v apps="$APPS" '$1 != apps' | sed 's/^/argo|/'; tf_releases "$ENV" | sed 's/^/terraform|/'; })
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

# --- platform -----------------------------------------------------------------
# The components every request crosses, held to more than `workloads` asks of an
# application. The gateway takes every request in; CoreDNS resolves every name;
# istiod issues the certificate ztunnel needs before a pod on a new node can open a
# connection; the Load Balancer Controller moves the ALB's targets as the gateway
# pods move; Karpenter provisions the capacity the drains need. One replica of any
# of them turns a single drain into an outage for every application at once — the
# hml 1.35→1.36 rehearsal lost requests to exactly that: an istiod moved mid-drain,
# and a pod started in that window could not connect.
#
# So these block, with or without --strict: two or more replicas, all available, the
# Ready ones on at least two nodes, under a PDB that allows a disruption now. And
# the per-node data plane — CNI, kube-proxy, ztunnel, istio-cni — has a Ready,
# current pod on every node. Gateways are found by label, so a second Gateway is
# held to the same bar without a change here.
CRITICAL=(kube-system/coredns kube-system/aws-load-balancer-controller kube-system/karpenter istio-system/istiod)
DATAPLANE_NAMESPACES='["kube-system", "istio-system"]'

# Fails (non-zero) when it cannot read the cluster: callers turn that into a
# finding, so an unreadable traffic path never passes as a healthy one.
critical_findings() {
  local DIR RC=0
  DIR=$(mktemp -d)
  # Files, not --argjson: every pod in the cluster is past the argument-size limit,
  # and jq failing there would print nothing — which reads as "no findings".
  printf '%s\n' "${CRITICAL[@]}" | jq -R . | jq -s . >"$DIR/want" &&
    kubectl get pdb -A -o json >"$DIR/pdbs" &&
    kubectl get pods -A -o json >"$DIR/pods" &&
    kubectl get ns -o json >"$DIR/ns" &&
    kubectl get deploy -A -o json >"$DIR/deploys" &&
    jq -r --slurpfile want "$DIR/want" --slurpfile pdbs "$DIR/pdbs" --slurpfile pods "$DIR/pods" --slurpfile ns "$DIR/ns" '
      def id: "\(.metadata.namespace)/\(.metadata.name)";
      def covers($labels): ((.spec.selector.matchLabels // {}) as $m
        | $m != {} and ($m | to_entries | all(. as $e | $labels[$e.key] == $e.value)));
      $want[0] as $want
      | [.items[] | select((id as $i | $want | index($i))
                           or (.spec.template.metadata.labels // {} | has("gateway.networking.k8s.io/gateway-name")))] as $crit
      | (($want - [$crit[] | id])[] | "\(.) — not found"),
        ($crit[]
         | . as $d | id as $i | ($d.spec.replicas // 1) as $n
         | [$pods[0].items[]
            | select(.metadata.namespace == $d.metadata.namespace and .metadata.deletionTimestamp == null)
            | (.metadata.labels // {}) as $l
            | select($d.spec.selector.matchLabels // {} | to_entries | all(. as $e | $l[$e.key] == $e.value))
            | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] as $ready
         | [$ready[].spec.nodeName] | unique as $nodes
         | ([$ns[0].items[] | select(.metadata.name == $d.metadata.namespace)
             | .metadata.labels["elbv2.k8s.aws/pod-readiness-gate-inject"]] | first) as $gated
         | [$pdbs[0].items[] | select(.metadata.namespace == $d.metadata.namespace)
            | select(covers($d.spec.template.metadata.labels // {}))] as $cover
         | if $n < 2 then "\($i) — \($n) replica"
           elif ($d.status.availableReplicas // 0) < $n then "\($i) — \($d.status.availableReplicas // 0)/\($n) available"
           elif ($nodes | length) < 2 then "\($i) — every Ready replica on one node (\($nodes | join(",")))"
           elif $gated == "enabled" and any($ready[]; (.spec.readinessGates // []) == [])
             then "\($i) — a pod started before its ALB readiness gate could be injected"
           elif ($cover | length) == 0 then "\($i) — no PodDisruptionBudget"
           elif ([$cover[] | .status.disruptionsAllowed // 0] | max) < 1 then "\($i) — its PodDisruptionBudget allows no disruption now"
           else empty end)' "$DIR/deploys" || RC=$?
  rm -rf "$DIR"
  return "$RC"
}

dataplane_findings() {
  kubectl get ds -A -o json | jq -r --argjson ns "$DATAPLANE_NAMESPACES" '.items[]
    | select(.metadata.namespace as $n | $ns | index($n))
    | .status.desiredNumberScheduled as $want
    | select(($want // 0) > 0)
    | select((.status.numberReady // 0) < $want
             or (.spec.updateStrategy.type == "RollingUpdate" and (.status.updatedNumberScheduled // 0) < $want))
    | "daemonset \(.metadata.namespace)/\(.metadata.name) — \(.status.numberReady // 0)/\($want) Ready, \(.status.updatedNumberScheduled // 0) current"'
}

argo_findings() {
  kubectl get crd applications.argoproj.io >/dev/null 2>&1 || return 0
  kubectl get applications -A -o json | jq -r '.items[]
    | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
    | "application \(.metadata.name) \(.status.sync.status)/\(.status.health.status)"'
}

# Two findings are left by the order a new cluster comes up in, not by a wrong
# setting, and a restart is their whole fix: replicas scheduled while only one node
# had registered (a topology spread counts the nodes that exist, and never moves a
# pod once placed), and gateway pods created before the TargetGroupBinding that
# their readiness gate is injected from. Every fresh hml has had one or both.
# --settle restarts just those Deployments — a rolling restart, under their PDB —
# and checks again; anything else still blocks.
SETTLEABLE='every Ready replica on one node|before its ALB readiness gate'

platform_bad() {
  {
    critical_findings || echo "could not read the traffic path's Deployments, pods and PDBs"
    dataplane_findings || echo "could not read the DaemonSets"
  } | sed '/^$/d'
}

cmd_platform() {
  local SETTLE=${1:-} BAD ID
  summary "### Traffic path"
  summary ""
  BAD=$(platform_bad)
  if [ -n "$BAD" ] && [ "$SETTLE" = --settle ] && grep -qE "$SETTLEABLE" <<<"$BAD"; then
    while read -r ID; do
      echo "settling $ID: $(grep -F "$ID — " <<<"$BAD" | head -1 | sed 's/.* — //')"
      kubectl -n "${ID%%/*}" rollout restart "deployment/${ID#*/}" </dev/null
      kubectl -n "${ID%%/*}" rollout status "deployment/${ID#*/}" --timeout=300s </dev/null
      summary "- Restarted \`$ID\` — $(grep -F "$ID — " <<<"$BAD" | head -1 | sed 's/.* — //')"
    done < <(grep -E "$SETTLEABLE" <<<"$BAD" | sed 's/ — .*//' | sort -u)
    BAD=$(platform_bad)
  fi
  if [ -z "$BAD" ]; then
    echo "traffic path: ${CRITICAL[*]} and every gateway — 2+ replicas on 2+ nodes, PDB allowing one out; data plane Ready on every node"
    summary "Gateways, ${CRITICAL[*]}: 2+ replicas on 2+ nodes, each under a PDB allowing a disruption. Node data plane Ready everywhere."
    return 0
  fi
  while read -r L; do echo "::error::traffic path: $L"; summary "- ❌ \`$L\`"; done <<<"$BAD"
  die "the traffic path would go down with a single drain — fix the components above (platform-gitops, or the add-on configuration in this repository), let them roll out, then rerun"
}

# --- karpenter ----------------------------------------------------------------
# Keeps the application nodes where they are until the platform has moved.
#
# The EC2NodeClass selects `al2023@latest`, and the alias resolves through an SSM
# path that carries the cluster's minor — so the moment the control plane reports
# the target, every Karpenter node is drifted, and Karpenter starts replacing them
# while the system node group is still rolling. Pinning the alias to a version does
# not help: the path still carries the minor. On hml that put the gateway, the
# applications and istiod in motion together.
#
# `karpenter.sh/do-not-disrupt` on a node stops every voluntary disruption of it —
# drift and consolidation; not expiry or a Spot interruption, which are not
# Karpenter's choice. It is set on the Node rather than in the NodePool, so nothing
# in Git changes and Argo CD has nothing to revert. Only nodes this step marked are
# released (label eks-upgrade/held), so an annotation someone set by hand survives.
#
# `hold` is repeated before each phase, which catches a node launched in between on
# the old image; one launched after the control plane moved is already on the new.
cmd_karpenter() {
  local NODES N
  case "${1:-}" in
    hold)
      NODES=$(kubectl get nodes -l 'karpenter.sh/nodepool,!eks-upgrade/held' -o json | jq -r '.items[]
        | select(.metadata.annotations["karpenter.sh/do-not-disrupt"] != "true") | .metadata.name')
      for N in $NODES; do
        kubectl annotate node "$N" karpenter.sh/do-not-disrupt=true --overwrite >/dev/null
        kubectl label node "$N" eks-upgrade/held=true --overwrite >/dev/null
        echo "held $N"
      done
      echo "Karpenter nodes held: $(kubectl get nodes -l eks-upgrade/held -o name | wc -l)"
      ;;
    release)
      for N in $(kubectl get nodes -l eks-upgrade/held -o name); do
        kubectl annotate "$N" karpenter.sh/do-not-disrupt- >/dev/null
        kubectl label "$N" eks-upgrade/held- >/dev/null
        echo "released ${N#node/}"
      done
      ;;
    *) die "usage: karpenter hold|release" ;;
  esac
}

# --- ami ----------------------------------------------------------------------
# Before Karpenter's nodes are released: every EC2NodeClass has resolved an image
# for the new minor. Drift launches the replacement from whatever the NodeClass
# resolved — still the old minor's image if Karpenter has not re-read the control
# plane yet (it re-resolves every 5 minutes), so the nodes would roll for nothing
# and `nodes` would time out an hour later; or no image at all if the alias has
# none for the minor, and then the cluster cannot launch a node.
#
# The alias lookup carries the control plane's minor in its SSM path, pinned
# (`al2023@v<release>`) or not (`@latest`) — Karpenter 1.13,
# pkg/providers/amifamily/al2023.go, resolvePath:
#   /aws/service/eks/optimized-ami/<minor>/amazon-linux-2023/<arch>/<variant>/...
# so the image it resolves is named for the minor, which is what is checked here:
#   amazon-eks-node-al2023-x86_64-standard-1.36-v20261019
# A NodeClass selecting images by ID or tag carries no such name; for it only
# AMIsReady is checked.
cmd_ami() {
  local TARGET=${1:?usage: ami <minor> <timeout s>} TIMEOUT=${2:?usage: ami <minor> <timeout s>}
  local DEADLINE=$((SECONDS + TIMEOUT)) BAD
  while :; do
    BAD=$(kubectl get ec2nodeclasses -o json | jq -r --arg t "$TARGET" '.items[] | .metadata.name as $n
      | (first(.status.conditions[]? | select(.type == "AMIsReady")) // {status: "Unknown", message: "no condition yet"}) as $c
      | if $c.status != "True" then "EC2NodeClass \($n): AMIsReady \($c.status) — \($c.message // "")"
        elif ((.status.amis // []) | length) == 0 then "EC2NodeClass \($n): no image resolved"
        elif any(.spec.amiSelectorTerms[]?; .alias) then
          (.status.amis[] | select(.name | contains("-\($t)-") | not)
            | "EC2NodeClass \($n): \(.id) \(.name) is not a \($t) image")
        else empty end') || BAD="could not read the EC2NodeClasses"
    if [ -z "$BAD" ]; then
      echo "every EC2NodeClass resolved a $TARGET image:"
      kubectl get ec2nodeclasses -o json | jq -r '.items[] | .metadata.name as $n | .status.amis[] | "  \($n)\t\(.id)\t\(.name)"' | sort -u
      return 0
    fi
    if [ $SECONDS -ge $DEADLINE ]; then
      while read -r L; do echo "::error::$L"; done <<<"$BAD"
      die "Karpenter did not resolve a $TARGET image within ${TIMEOUT}s — releasing its nodes would replace them with nothing better. kubectl describe ec2nodeclass"
    fi
    echo "$(date +%T) waiting on $(wc -l <<<"$BAD") item(s), e.g. $(head -1 <<<"$BAD")"
    sleep 30
  done
}

# --- probe --------------------------------------------------------------------
# Availability measured, not inferred: a loop on the bastion requesting <path>
# through the internal ingress ALB, five times a second, for the whole upgrade.
#
# The bastion because it is the one host no phase replaces — a probe pod would be
# evicted by the drains it is meant to observe, and its counts with it. And through
# the ALB because that is the path a client takes: target registration, the
# gateway's drain and the readiness gate are all on it, and none is on a request
# made to the Service from inside the cluster.
#
# Results stay on the bastion (one line per request: epoch, HTTP code) and are
# split by the phase marks the workflow writes, so a failure is attributed to the
# phase that caused it.
PROBE_LOG=/var/log/eks-upgrade-probe.log
PROBE_UNIT=eks-upgrade-probe

env_load() {
  local FILE
  FILE=$(tfvars "$1")
  REGION=$(tfvar "$FILE" region)
  PROJECT=$(tfvar "$FILE" project_name)
}

bastion_id() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$PROJECT-bastion" Name=instance-state-name,Values=running \
    --query 'Reservations[0].Instances[0].InstanceId' --output text
}

# Runs a shell script on an instance through SSM and prints its stdout.
ssm_run() {
  local ID OUT
  ID=$(aws ssm send-command --region "$REGION" --instance-ids "$1" --document-name AWS-RunShellScript \
    --parameters "$(jq -cn --arg c "$2" '{commands: [$c]}')" --query Command.CommandId --output text) || return 1
  aws ssm wait command-executed --region "$REGION" --command-id "$ID" --instance-id "$1" 2>/dev/null || true
  OUT=$(aws ssm get-command-invocation --region "$REGION" --command-id "$ID" --instance-id "$1" --output json)
  [ "$(jq -r .Status <<<"$OUT")" = Success ] || { jq -r .StandardErrorContent <<<"$OUT" >&2; return 1; }
  jq -r .StandardOutputContent <<<"$OUT"
}

# "requests failures" over the last N lines of the probe log, or "inactive".
probe_tail() {
  ssm_run "$1" "systemctl is-active -q $PROBE_UNIT || { echo inactive; exit 0; }
tail -n $2 $PROBE_LOG | awk '{ n++; if (\$2 != 200) f++ } END { print n + 0, f + 0 }'"
}

cmd_probe() {
  local ACTION=${1:-} ENV=${2:?usage: probe start <env> <path> | probe report <env> <marks file> [--strict]}
  env_load "$ENV"
  local ID
  ID=$(bastion_id)
  [ -n "$ID" ] && [ "$ID" != None ] || die "no running instance tagged $PROJECT-bastion to probe from"

  case "$ACTION" in
    start)
      local PROBE_PATH=${3:?usage: probe start <env> <path>} DNS URL N F
      DNS=$(aws elbv2 describe-load-balancers --region "$REGION" --names "$PROJECT-platform-ingress" \
        --query 'LoadBalancers[0].DNSName' --output text) || die "no load balancer $PROJECT-platform-ingress"
      URL="http://$DNS$PROBE_PATH"
      # A transient systemd unit: it outlives the SSM command, a rerun replaces it,
      # and RuntimeMaxSec stops it even if no report ever runs.
      ssm_run "$ID" "systemctl stop $PROBE_UNIT 2>/dev/null; systemctl reset-failed $PROBE_UNIT 2>/dev/null
: >$PROBE_LOG
systemd-run --quiet --unit=$PROBE_UNIT --property=RuntimeMaxSec=14400 /bin/bash -c 'while :; do echo \"\$(date +%s) \$(curl -s -o /dev/null -m 2 -w %{http_code} $URL)\" >>$PROBE_LOG; sleep 0.2; done'" >/dev/null \
        || die "could not start the probe on $ID"
      # Before anything moves the path must answer, or the probe would measure that
      # instead of the upgrade.
      sleep 20
      read -r N F <<<"$(probe_tail "$ID" 1000)"
      [ "${N:-0}" -gt 0 ] && [ "${F:-1}" -eq 0 ] \
        || die "baseline: ${F:-?} of ${N:-0} requests to $URL failed before anything moved — fix the path or pass another probe path (code 000 is no connection at all: the bastion's egress, or the ALB's security group)"
      echo "probe: $URL from $ID — $N requests before the upgrade, all 200"
      summary "Availability probe: \`GET $PROBE_PATH\` through the ingress ALB, from the bastion."
      ;;

    report)
      local MARKS=${3:?usage: probe report <env> <marks file> [--strict]} STRICT=${4:-} T OUT
      T=$(cut -d' ' -f1 "$MARKS" | paste -sd' ')
      OUT=$(ssm_run "$ID" "systemctl stop $PROBE_UNIT 2>/dev/null
awk -v marks='$T' 'BEGIN { m = split(marks, t, \" \") }
  { p = 0; for (i = 1; i <= m; i++) if (\$1 >= t[i]) p = i
    if (\$2 == 200) ok[p]++; else { bad[p]++; if (!first[p]) first[p] = \$1 } }
  END { for (i = 0; i <= m; i++) print i, ok[i] + 0, bad[i] + 0, first[i] + 0 }' $PROBE_LOG") \
        || die "could not read the probe's results from $ID"

      summary ""
      summary "### Availability through the upgrade"
      summary ""
      summary "| Phase | Requests OK | Failed | First failure (UTC) |"
      summary "|---|---|---|---|"
      local I OK BAD FIRST LABEL TOTAL_OK=0 TOTAL_BAD=0
      while read -r I OK BAD FIRST; do
        if [ "$I" -eq 0 ]; then LABEL="before the first phase"; else LABEL=$(sed -n "${I}p" "$MARKS" | cut -d' ' -f2-); fi
        [ "$FIRST" -gt 0 ] && FIRST=$(date -u -d "@$FIRST" +%T) || FIRST="—"
        printf '  %-28s ok %-6s failed %-4s first %s\n' "$LABEL" "$OK" "$BAD" "$FIRST"
        summary "| $LABEL | $OK | $([ "$BAD" -gt 0 ] && echo "**$BAD**" || echo 0) | $FIRST |"
        TOTAL_OK=$((TOTAL_OK + OK)) TOTAL_BAD=$((TOTAL_BAD + BAD))
      done <<<"$OUT"
      summary "| **total** | $TOTAL_OK | $TOTAL_BAD | |"

      if [ "$TOTAL_BAD" -eq 0 ]; then
        echo "availability: $TOTAL_OK requests through the upgrade, none failed"
      elif [ "$STRICT" = --strict ]; then
        die "availability: $TOTAL_BAD of $((TOTAL_OK + TOTAL_BAD)) requests failed during the upgrade"
      else
        warn "availability: $TOTAL_BAD of $((TOTAL_OK + TOTAL_BAD)) requests failed during the upgrade — the table in the summary says in which phase"
      fi
      ;;

    *) die "usage: probe start <env> <path> | probe report <env> <marks file> [--strict]" ;;
  esac
}

# --- apply --------------------------------------------------------------------
# One phase = one targeted, saved plan, applied as planned. Not -detailed-exitcode:
# in CI `terraform` is hashicorp/setup-terraform's wrapper, which reports exit 2
# ("changes") as 0 — the first hml upgrade printed "no changes" under a plan moving
# 1.35 -> 1.36 and applied nothing. An empty saved plan applies as a no-op, so a
# resumed run still passes through phases already done.
cmd_apply() {
  local ENV=${1:?usage: apply <env> <target address>} TARGET=${2:?usage: apply <env> <target address>}
  terraform -chdir=foundation plan -input=false -out=tfplan \
    -target="$TARGET" -var-file="environments/$ENV/terraform.tfvars" ||
    die "plan for $TARGET failed"
  terraform -chdir=foundation apply -input=false -auto-approve tfplan
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

# --- health -------------------------------------------------------------------
# The gate between phases: the next one starts only on a cluster that has
# recovered from the last. Every node Ready, the per-node data plane complete, the
# traffic path back to two-on-two-nodes, every Application Synced and Healthy — and,
# while the probe runs, the last fifty requests through the ALB answered.
#
# Not a version check: that is `nodes` for each phase and `verify` at the end.
cmd_health() {
  local ENV=${1:?usage: health <env> <timeout s>} TIMEOUT=${2:?usage: health <env> <timeout s>}
  local DEADLINE=$((SECONDS + TIMEOUT)) BAD ID="" N F
  env_load "$ENV"
  ID=$(bastion_id 2>/dev/null || true)
  [ "$ID" = None ] && ID=""
  while :; do
    BAD=$(
      kubectl get nodes -o json | jq -r '.items[]
        | select((any(.status.conditions[]; .type == "Ready" and .status == "True") | not) or .spec.unschedulable)
        | "node \(.metadata.name) not Ready or cordoned"'
      dataplane_findings || echo "could not read the DaemonSets"
      critical_findings || echo "could not read the traffic path's Deployments, pods and PDBs"
      argo_findings || echo "could not read the Argo CD Applications"
      if [ -n "$ID" ]; then
        read -r N F <<<"$(probe_tail "$ID" 50 || echo inactive)"
        [ "$N" = inactive ] || [ "${F:-0}" -eq 0 ] || echo "probe — $F of the last $N requests through the ALB failed"
      fi
    )
    BAD=$(sed '/^$/d' <<<"$BAD")
    if [ -z "$BAD" ]; then
      echo "healthy: nodes Ready, data plane complete, traffic path redundant, Applications Synced/Healthy${ID:+, probe answering}"
      return 0
    fi
    if [ $SECONDS -ge $DEADLINE ]; then
      while read -r L; do echo "::error::$L"; done <<<"$BAD"
      die "the cluster did not recover within ${TIMEOUT}s — the next phase would start on top of this"
    fi
    echo "$(date +%T) waiting on $(wc -l <<<"$BAD") item(s), e.g. $(head -1 <<<"$BAD")"
    sleep 20
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
      argo_findings || echo "could not read the Argo CD Applications"
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
  platform) cmd_platform "$@" ;;
  karpenter) cmd_karpenter "$@" ;;
  ami) cmd_ami "$@" ;;
  probe) cmd_probe "$@" ;;
  apply) cmd_apply "$@" ;;
  nodes) cmd_nodes "$@" ;;
  health) cmd_health "$@" ;;
  verify) cmd_verify "$@" ;;
  *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

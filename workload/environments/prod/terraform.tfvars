# =============================================================================
# prod — workload layer
#
# NOT DEPLOYED. The backend.hcl in this directory still points at the
# homologation account's state bucket, and so do the values below. Both must be
# corrected once the production account exists.
# =============================================================================

# --- Region -------------------------------------------------------------------
region = "us-east-1"

# --- Foundation state ---------------------------------------------------------
# TODO: this bucket lives in the homologation account. Pointing production at it
# would write production state into the wrong account — correct before applying.
foundation_state_bucket = "eks-development-tfstate-889384902110"
foundation_state_key    = "foundation/prod/terraform.tfstate"

# --- Chart versions -----------------------------------------------------------
# Production should lag hml deliberately: a chart version proves itself there
# first. Today both track 10.4.0 because hml is the only environment that exists.
argocd_chart_version = "10.4.0"

# --- Storage ------------------------------------------------------------------
# Retain: deleting a PVC must never destroy production data. The cost is that a
# retained volume is left in Released state, outside Terraform's knowledge, and
# keeps billing after the claim is gone. Reclaiming it is a deliberate act, which
# is the point.
storage_reclaim_policy = "Retain"

# --- GitOps -------------------------------------------------------------------
# The root Application tracks this repository; the platform AppProject accepts no
# other source. Tracking a branch means Argo follows every commit — acceptable in
# prod, where a bad sync is cheap to fix.
platform_repo_url      = "https://github.com/gulinux86/platform-gitops"
platform_repo_revision = "main"

# Declared before the repository exists, so the boundary is written first.
apps_repo_url = "https://github.com/gulinux86/app-gitops"

# Prefix glob: a new application needs no Terraform change, and system namespaces
# stay out of reach because they do not match.
apps_namespaces = ["app-*"]

# Chart repositories count as sources. A multi-source Application pulls its chart
# from one and its values from another, and Argo CD checks both — listing only the
# Git repository fails every chart-based component with "repo is not permitted".
platform_source_repos = [
  "https://github.com/gulinux86/platform-gitops",
  "https://github.com/kubernetes-sigs/gateway-api",
  "https://charts.jetstack.io",
  "https://istio-release.storage.googleapis.com/charts",
]

apps_source_repos = ["https://github.com/gulinux86/app-gitops"]

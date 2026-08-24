# =============================================================================
# hml — workload layer
#
# This layer reads the foundation layer's outputs through terraform_remote_state,
# so it needs to know where that state lives. Everything else is declared here
# explicitly; the root variables carry no defaults.
# =============================================================================

# --- Region -------------------------------------------------------------------
region = "us-east-1"

# --- Foundation state ---------------------------------------------------------
# Where to read the foundation layer's outputs from. Must match the bucket and key
# in foundation/environments/hml/backend.hcl, or this layer silently reads a
# different environment's cluster.
foundation_state_bucket = "eks-development-tfstate-889384902110"
foundation_state_key    = "foundation/hml/terraform.tfstate"

# --- Chart versions -----------------------------------------------------------
# Pinned, not defaulted: an unpinned chart means a rebuild can install a different
# Argo CD than the one that was reviewed.
argocd_chart_version = "10.4.0"

# --- Storage ------------------------------------------------------------------
# Delete here, Retain in production. hml is torn down and rebuilt between
# sessions, and a retained volume outlives `terraform destroy` — it is left in
# Released state, outside Terraform's knowledge, and keeps billing. Over enough
# cycles those orphans accumulate silently.
#
# The data in this environment is disposable by definition, so the protection
# Retain buys is worth nothing here and the cleanup it costs is worth avoiding.
storage_reclaim_policy = "Delete"

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

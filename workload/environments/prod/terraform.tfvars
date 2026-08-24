region                  = "us-east-1"
foundation_state_bucket = "eks-development-tfstate-889384902110"
foundation_state_key    = "foundation/prod/terraform.tfstate"

# Retain: deleting a PVC must never destroy production data. This matches the
# module default, and is written out anyway — a policy this consequential should be
# readable in the environment's own file, not inferred from a default somewhere
# else. hml deliberately sets the opposite.
#
# The cost is that a retained volume is left in Released state, outside Terraform's
# knowledge, and keeps billing after the claim is gone. Reclaiming it is a
# deliberate act, which is the point.
storage_reclaim_policy = "Retain"

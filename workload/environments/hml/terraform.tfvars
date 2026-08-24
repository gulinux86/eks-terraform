region                  = "us-east-1"
foundation_state_bucket = "eks-development-tfstate-889384902110"
foundation_state_key    = "foundation/hml/terraform.tfstate"

# Delete here, Retain everywhere else. hml is torn down and rebuilt between
# sessions, and a retained volume outlives `terraform destroy` — it is left in
# Released state, outside Terraform's knowledge, and keeps billing. Over enough
# cycles those orphans accumulate silently.
#
# The data in this environment is disposable by definition, so the protection
# Retain buys is worth nothing here and the cleanup it costs is worth avoiding.
# Production keeps the module default (Retain), where the trade runs the other way.
storage_reclaim_policy = "Delete"

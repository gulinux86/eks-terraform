# Declared here, not only in the layer, so the module can be initialised and tested
# on its own — which is how this repository's test convention works
# (`terraform -chdir=<module> init -backend=false && terraform -chdir=<module> test`).
#
# Without this the module inherits nothing and a standalone `init` resolves the
# newest provider available. Helm 3 turned `set` from a block into an attribute, so
# `binding.tf` fails to parse under it while working correctly in the layer, which
# pins 2.12.1. Found by writing the test suite, not in production.
#
# The constraints are compatible with `workload/provider.tf`; that file still owns
# the exact pins.
terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

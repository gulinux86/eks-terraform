# Declared here so the module can be initialised and tested on its own, the
# repository's test convention. Compatible with workload/provider.tf, which owns the
# exact pins.
terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

terraform {
  required_version = "~> 1.10"

  # Local state on purpose: bootstrap solves the chicken-and-egg problem
  # (it creates the role/state access that the other layers rely on), so it
  # cannot itself depend on a remote backend. Apply it once, per account,
  # with administrator credentials.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

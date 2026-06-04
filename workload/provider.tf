terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.25.2"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "2.12.1"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = data.terraform_remote_state.foundation.outputs.tags
  }
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.foundation.outputs.endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.foundation.outputs.certificate_authority)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.foundation.outputs.cluster_name]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.foundation.outputs.endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.foundation.outputs.certificate_authority)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.foundation.outputs.cluster_name]
      command     = "aws"
    }
  }
}

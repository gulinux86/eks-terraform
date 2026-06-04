variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(any)
  description = "Tags to be added to AWS resources"
}

variable "oidc" {
  type        = string
  description = "HTTPS URL from OIDC provider of the EKS cluster"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"

}

variable "region" {
  type        = string
  description = "AWS region where the cluster runs (passed explicitly to the controller)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where load balancers are provisioned (passed explicitly to the controller)"
}
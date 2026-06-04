variable "cidr_block" {
  type        = string
  description = "Networking CIDR block to be used for the VPC"
}

variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "region" {
  type        = string
  description = "AWS region to create the resources"
}

variable "tags" {
  type        = map(any)
  description = "A map of tags to add to all AWS resources"
}

variable "endpoint_public_access" {
  type        = bool
  description = "Expose the EKS API server publicly so Terraform (GitHub-hosted runners) and operators can reach it. Private access remains enabled."
  default     = true
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API endpoint. Tighten this per environment (e.g. office/CI egress ranges)."
  default     = ["0.0.0.0/0"]
}

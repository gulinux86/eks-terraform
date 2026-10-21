variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(string)
  description = "Tags to be added to AWS resources"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name to create Management Node Group"

}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor version for the nodes (e.g. \"1.35\"). Pass the cluster's version: the group then rolls onto it whenever the control plane moves."

  # Required, no default. A default here would be a second place the version lives,
  # and the one nobody bumps.
  validation {
    condition     = can(regex("^1\\.\\d{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version like \"1.35\" — no patch component, no \"v\" prefix."
  }
}

variable "subnet_private_1a" {
  type        = string
  description = "Subnet ID from AZ 1a"
}

variable "subnet_private_1b" {
  type        = string
  description = "Subnet ID from AZ 1b"
}

variable "instance_types" {
  type        = list(string)
  description = "EC2 instance types for the node group"
  default     = ["t3.medium"]

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "instance_types must list at least one EC2 instance type."
  }
}

variable "ami_type" {
  type        = string
  description = "AMI type for the managed node group (AL2 is end-of-life; AL2023 is the current default)"
  default     = "AL2023_x86_64_STANDARD"
}

variable "desired_size" {
  type        = number
  description = "Desired number of nodes"
  default     = 2

  # Cross-variable validation (Terraform >= 1.9). AWS rejects an incoherent scaling
  # config, but only once it is creating the node group — after the VPC, cluster and
  # IAM roles are already built.
  validation {
    condition     = var.desired_size >= var.min_size && var.desired_size <= var.max_size
    error_message = "node sizing must satisfy min_size <= desired_size <= max_size."
  }
}

variable "min_size" {
  type        = number
  description = "Minimum number of nodes"
  default     = 1
}

variable "max_size" {
  type        = number
  description = "Maximum number of nodes"
  default     = 4
}
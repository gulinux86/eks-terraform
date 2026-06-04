variable "region" {
  type        = string
  description = "AWS region (IAM is global, but the provider needs a region)"
  default     = "us-east-1"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository allowed to assume the role, as owner/name"
  default     = "gulinux86/eks-terraform"
}

variable "role_name" {
  type        = string
  description = "Name of the IAM role GitHub Actions will assume via OIDC"
  default     = "github-actions-eks-terraform"
}

variable "state_bucket_name" {
  type        = string
  description = "S3 bucket that stores the foundation/workload remote state. Must match the bucket in environments/<env>/backend.hcl."
  default     = "eks-development-tfstate-889384902110"
}

variable "policy_arn" {
  type        = string
  description = "Managed policy attached to the CI role. AdministratorAccess is a deliberate bootstrap simplification — scope it down with a custom policy / permission boundary for real production."
  default     = "arn:aws:iam::aws:policy/AdministratorAccess"
}

variable "tags" {
  type        = map(any)
  description = "Tags applied to the created IAM resources"
  default = {
    Project   = "eks"
    ManagedBy = "terraform"
    Layer     = "bootstrap"
  }
}

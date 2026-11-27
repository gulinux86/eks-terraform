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

variable "environment" {
  type        = string
  description = "Environment this AWS account serves (hml or prod). The deploy role trusts only this environment's GitHub Environment claim, so bootstrapping an account is a deliberate choice — there is no default."

  validation {
    condition     = contains(["hml", "prod"], var.environment)
    error_message = "environment must be \"hml\" or \"prod\" — it becomes the GitHub Environment name in the deploy role's OIDC trust policy."
  }
}

variable "plan_role_name" {
  type        = string
  description = "Name of the read-only IAM role assumed by terraform-plan"
  default     = "github-actions-eks-plan"
}

variable "deploy_role_name" {
  type        = string
  description = "Name of the write-capable IAM role assumed by terraform-deploy and terraform-destroy"
  default     = "github-actions-eks-deploy"
}

variable "state_bucket_name" {
  type        = string
  description = "S3 bucket that stores the foundation/workload remote state. Must match the bucket in environments/<env>/backend.hcl."
  default     = "eks-development-tfstate-889384902110"
}

variable "plan_policy_arn" {
  type        = string
  description = "Managed policy attached to the plan role. Read-only by design; the role additionally gets an inline kms:Decrypt grant on the state key, which ReadOnlyAccess does not cover."
  default     = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

variable "deploy_policy_arn" {
  type        = string
  description = "Managed policy attached to the deploy role. AdministratorAccess remains a known gap (ARCHITECTURE.md §12): sizing a custom policy for EKS is iterative and was deliberately deferred, since the role split already removes this credential from pull-request reach."
  default     = "arn:aws:iam::aws:policy/AdministratorAccess"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the created IAM resources"
  default = {
    Project   = "eks"
    ManagedBy = "terraform"
    Layer     = "bootstrap"
  }
}

variable "ecr_push_subject_prefixes" {
  type        = list(string)
  description = "OIDC subject prefixes (everything before `:ref:`) of the repositories whose main-branch release workflow may push images to apps/* in ECR. Both GitHub subject formats: repo:<owner>/<repo> and the immutable repo:<owner>@<owner id>/<repo>@<repo id>; * matches any repository. Pull requests never get the push role."
  default = [
    "repo:gulinux86/*",
    "repo:gulinux86@37779157/*",
  ]
}

variable "ecr_push_role_name" {
  type        = string
  description = "Name of the role application release workflows push to ECR with"
  default     = "github-actions-ecr-push"
}

variable "gitops_subject_prefixes" {
  type        = list(string)
  description = "OIDC subject prefixes of the application GitOps repository, in both GitHub subject formats. Its CI reads the images its values files pin, on pull requests and branch pushes."
  default = [
    "repo:gulinux86/app-gitops",
    "repo:gulinux86@37779157/app-gitops@1430119042",
  ]
}

variable "ecr_read_role_name" {
  type        = string
  description = "Name of the read-only role app-gitops' CI reads images with"
  default     = "github-actions-ecr-read"
}

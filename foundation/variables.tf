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

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster. Pin a version in standard support (avoid extended-support versions)."
  default     = "1.34"
}

variable "instance_types" {
  type        = list(string)
  description = "EC2 instance types for the managed node group. On a new AWS account under the Free Plan, only free-tier-eligible types launch (e.g. t3.small, t3.micro, c7i-flex.large, m7i-flex.large)."
  default     = ["t3.small"]
}

variable "desired_size" {
  type        = number
  description = "Desired number of nodes"
  default     = 1
}

variable "min_size" {
  type        = number
  description = "Minimum number of nodes"
  default     = 1
}

variable "max_size" {
  type        = number
  description = "Maximum number of nodes"
  default     = 2
}

variable "endpoint_public_access" {
  type        = bool
  description = "Expose the EKS API server publicly so Terraform (GitHub-hosted runners) and operators can reach it. Private access remains enabled."
  default     = true
}

variable "cluster_admin_role_arns" {
  type        = list(string)
  description = "IAM principals granted EKS cluster-admin (typically the CI/CD deploy role that runs Terraform). Needed so the workload layer's kubernetes/helm providers are authorized."
  default     = []
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API endpoint. Tighten this per environment (e.g. office/CI egress ranges)."
  default     = ["0.0.0.0/0"]
}

variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(any)
  description = "Tags to be added to AWS resources"
}

variable "private_subnet_1a" {
  type        = string
  description = "Private subnet to create EKS cluster ENI in AZ 1a"
}

variable "private_subnet_1b" {
  type        = string
  description = "Private subnet to create EKS cluster ENI in AZ 1b"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block used to restrict API server access"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.35"
}

variable "cluster_log_types" {
  type        = list(string)
  description = "EKS control plane log types to enable"
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "admin_role_arns" {
  type        = list(string)
  description = "IAM role/user ARNs granted cluster-admin via EKS Access Entries (typically the CI/CD deploy role). Required because AWS provider v6 does not bootstrap creator admin permissions by default."
  default     = []
}

variable "endpoint_public_access" {
  type        = bool
  description = "Expose the EKS API server publicly. Required when Terraform runs from outside the VPC (e.g. GitHub-hosted runners). Private access stays enabled regardless."
  default     = true
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API endpoint. Restrict in prod; defaults to open for portfolio/demo use."
  default     = ["0.0.0.0/0"]
}
variable "cidr_block" {
  type        = string
  description = "Networking CIDR block to be used for the VPC"

  # Subnet CIDRs are derived from this; a malformed value fails later, pointing at
  # the derived subnet instead of the input that caused it.
  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR, e.g. \"10.0.0.0/16\"."
  }
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
  type        = map(string)
  description = "A map of tags to add to all AWS resources"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster. Pin a version in standard support (avoid extended-support versions)."
  validation {
    condition     = can(regex("^1\\.\\d{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version like \"1.35\" — no patch component, no \"v\" prefix."
  }
}

variable "vpc_cni_version" {
  type        = string
  description = "Pin the vpc-cni add-on version. Null resolves the latest compatible with kubernetes_version."
}

variable "coredns_version" {
  type        = string
  description = "Pin the coredns add-on version. Null resolves the latest compatible with kubernetes_version."
}

variable "kube_proxy_version" {
  type        = string
  description = "Pin the kube-proxy add-on version. Null resolves the latest compatible with kubernetes_version."
}

variable "instance_types" {
  type        = list(string)
  description = "EC2 instance types for the managed node group. On a new AWS account under the Free Plan, only free-tier-eligible types launch (e.g. t3.small, t3.micro, c7i-flex.large, m7i-flex.large)."

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "instance_types must list at least one EC2 instance type."
  }
}

variable "desired_size" {
  type        = number
  description = "Desired number of nodes"
  validation {
    condition     = var.desired_size >= var.min_size && var.desired_size <= var.max_size
    error_message = "node sizing must satisfy min_size <= desired_size <= max_size."
  }
}

variable "min_size" {
  type        = number
  description = "Minimum number of nodes"
}

variable "max_size" {
  type        = number
  description = "Maximum number of nodes"
}

variable "endpoint_public_access" {
  type        = bool
  description = "Expose the EKS API server publicly so Terraform (GitHub-hosted runners) and operators can reach it. Private access remains enabled."
}

variable "cluster_admin_role_arns" {
  type        = list(string)
  description = "IAM principals granted EKS cluster-admin (typically the CI/CD deploy role that runs Terraform). Needed so the workload layer's kubernetes/helm providers are authorized. Required — see the validation below."

  # An empty list applies cleanly and yields a cluster nobody can administer,
  # including the pipeline. There is no valid default, so there is no default.
  validation {
    condition     = length(var.cluster_admin_role_arns) > 0
    error_message = "cluster_admin_role_arns must not be empty: with no access entry, neither CI nor an operator can reach the Kubernetes API."
  }

  validation {
    # The account root (`...:root`, no trailing path) is accepted deliberately.
    # An earlier version of this rule allowed only role/ and user/ on the
    # assumption that EKS rejects root as an access-entry principal — it does not.
    condition     = alltrue([for a in var.cluster_admin_role_arns : can(regex("^arn:aws[a-z-]*:iam::\\d{12}:((role|user)/.+|root)$", a))])
    error_message = "each cluster_admin_role_arns entry must be an IAM role ARN, user ARN, or the account root ARN (arn:aws:iam::123456789012:root)."
  }
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API endpoint. Tighten this per environment (e.g. office/CI egress ranges)."
}

variable "log_retention_days" {
  type        = number
  description = "Retention for the EKS control-plane log group. Unmanaged, EKS creates it with no expiry and audit logs accumulate forever."
}

variable "metrics_server_version" {
  type        = string
  description = "metrics-server add-on version. Required, like every other add-on version: an unpinned add-on resolves to whatever is latest at apply time, so two applies months apart install different software with no diff in the code."
}

variable "ebs_csi_version" {
  type        = string
  description = "aws-ebs-csi-driver add-on version. Required for the same reason."
}

variable "pod_identity_agent_version" {
  type        = string
  description = "eks-pod-identity-agent add-on version. Required for the same reason."
}

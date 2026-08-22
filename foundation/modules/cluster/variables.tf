variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(string)
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

  # EKS takes a minor version only ("1.35"). A patch version or a "v" prefix is
  # accepted by Terraform and rejected by the AWS API well into the apply.
  validation {
    condition     = can(regex("^1\\.\\d{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version like \"1.35\" — no patch component, no \"v\" prefix."
  }
}

variable "cluster_log_types" {
  type        = list(string)
  description = "EKS control plane log types to enable"
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  type        = number
  description = "Retention for the EKS control-plane log group. Left unmanaged, EKS creates the group itself with no expiry and audit logs accumulate forever. 90 days is a forensic window that still bounds cost. NOTE: if a cluster previously existed in the account the log group survives it — import it (terraform import) rather than deleting, which would discard audit history."
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

variable "admin_role_arns" {
  type        = list(string)
  description = "IAM role/user ARNs granted cluster-admin via EKS Access Entries (typically the CI/CD deploy role). Required because AWS provider v6 does not bootstrap creator admin permissions by default."

  # An empty list plans and applies cleanly, producing a cluster nobody can
  # administer — including the pipeline. Failing here is much cheaper.
  validation {
    condition     = length(var.admin_role_arns) > 0
    error_message = "admin_role_arns must not be empty: with no access entry, neither CI nor an operator can reach the Kubernetes API."
  }

  validation {
    # The account root (`...:root`, no trailing path) is accepted deliberately.
    # An earlier version of this rule allowed only role/ and user/ on the
    # assumption that EKS rejects root as an access-entry principal — it does not.
    condition     = alltrue([for a in var.admin_role_arns : can(regex("^arn:aws[a-z-]*:iam::\\d{12}:((role|user)/.+|root)$", a))])
    error_message = "each admin_role_arns entry must be an IAM role ARN, user ARN, or the account root ARN (arn:aws:iam::123456789012:root)."
  }

  # No default on purpose: the previous `default = []` was a value the module could
  # never legitimately use, since an empty list yields a cluster nobody can reach.
  # A required input says that out loud instead of failing later.
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
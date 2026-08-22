variable "cidr_block" {
  type        = string
  description = "Networking CIDR block to be used for the VPC"

  # Subnet CIDRs are derived from this with cidrsubnet(). A malformed value fails
  # only once the derived subnets are evaluated, with an error pointing at the
  # subnet rather than at the input that caused it.
  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR, e.g. \"10.0.0.0/16\"."
  }
}

variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(string)
  description = "Tags to be added to AWS resources"
}

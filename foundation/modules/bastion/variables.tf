variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(string)
  description = "Tags to be added to AWS resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the bastion will be created"
}

variable "private_subnet_id" {
  type        = string
  description = "Private subnet ID to launch the bastion host"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name the bastion will manage via kubectl"
}

variable "region" {
  type        = string
  description = "AWS region (used to configure kubeconfig on the bastion)"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the bastion host"
  default     = "t3.micro"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR. Used to scope the bastion egress to in-VPC HTTPS/DNS (SSM interface endpoints + private EKS API) instead of 0.0.0.0/0."
}

variable "kubectl_version" {
  type        = string
  description = "kubectl version (full x.y.z) to install from the in-region tooling bucket, reached via the S3 gateway endpoint with no internet egress. The deploy workflow seeds that exact version from AWS's amazon-eks bucket, discovering the newest build date there. Keep within one minor of the cluster version."
  default     = "1.35.0"
}

variable "manage_ssm_session_shell" {
  type        = bool
  description = "Create the account-wide SSM-SessionManagerRunShell document so sessions start a login shell (making /etc/profile.d apply). Only one such document can exist per account, so set false if another environment in the same account already owns it."
  default     = true
}

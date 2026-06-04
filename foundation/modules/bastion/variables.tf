variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(any)
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

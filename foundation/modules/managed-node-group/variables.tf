variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(any)
  description = "Tags to be added to AWS resources"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name to create Management Node Group"

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
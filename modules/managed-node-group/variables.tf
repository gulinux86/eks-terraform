variable "project_name" {
  type        = string
  description = "Project name to be used to name the resouces (Name tag)"
}

variable "tags" {
  type        = map(any)
  description = "Tags to be added to AWS resources"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name to create Managment Node Group"

}

variable "subnet_private_1a" {
  type        = string
  description = "Subnet ID from AZ a1"
}

variable "subnet_private_1b" {
  type        = string
  description = "Subnet ID from AZ b1"
}
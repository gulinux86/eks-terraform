variable "project_name" {
  type        = string
  description = "Project name to be used to name the resources (Name tag)"
}

variable "tags" {
  type        = map(any)
  description = "Tags to be added to AWS resources"
}

variable "region" {
  type        = string
  description = "AWS region (used to build the endpoint service names)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the endpoints will be created"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR allowed to reach the interface endpoints on 443"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets where interface endpoints ENIs are placed"
}

variable "private_route_table_ids" {
  type        = list(string)
  description = "Private route tables to associate with the S3 gateway endpoint"
}

variable "interface_services" {
  type        = list(string)
  description = "AWS service short names for interface (PrivateLink) endpoints"
  default = [
    "ecr.api",              # ECR authentication
    "ecr.dkr",              # ECR image pulls
    "sts",                  # IRSA / assume role
    "ec2",                  # CNI and node lifecycle
    "eks",                  # eks:DescribeCluster (bastion update-kubeconfig)
    "kms",                  # envelope encryption of cluster secrets
    "elasticloadbalancing", # AWS Load Balancer Controller
    "autoscaling",          # cluster/node autoscaling
    "logs",                 # CloudWatch Logs (control plane / apps)
    "ssm",                  # Session Manager (bastion)
    "ssmmessages",          # Session Manager data channel
    "ec2messages"           # SSM agent control channel
  ]
}

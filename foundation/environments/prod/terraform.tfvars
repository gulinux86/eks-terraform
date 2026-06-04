cidr_block   = "10.1.0.0/16"
project_name = "eks-prod"
region       = "us-east-1"

tags = {
  Project     = "eks"
  Environment = "prod"
  ManagedBy   = "terraform"
}

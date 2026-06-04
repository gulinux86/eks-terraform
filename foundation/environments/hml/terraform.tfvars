cidr_block   = "10.0.0.0/16"
project_name = "eks-hml"
region       = "us-east-1"

tags = {
  Project     = "eks"
  Environment = "hml"
  ManagedBy   = "terraform"
}

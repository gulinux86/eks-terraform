cidr_block         = "10.1.0.0/16"
project_name       = "eks-prod"
region             = "us-east-1"
kubernetes_version = "1.34"

# Production sizing — requires a paid AWS account (these types are not free-tier).
instance_types = ["t3.medium"]
desired_size   = 2
min_size       = 2
max_size       = 4

tags = {
  Project     = "eks"
  Environment = "prod"
  ManagedBy   = "terraform"
}

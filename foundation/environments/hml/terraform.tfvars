cidr_block         = "10.0.0.0/16"
project_name       = "eks-hml"
region             = "us-east-1"
kubernetes_version = "1.34"

# Free-tier-eligible node (new-account Free Plan only allows these types).
# t3.small = 2 vCPU / 2 GiB, x86_64 (matches the AL2023 x86_64 AMI).
instance_types = ["t3.small"]
desired_size   = 1
min_size       = 1
max_size       = 2

tags = {
  Project     = "eks"
  Environment = "hml"
  ManagedBy   = "terraform"
}

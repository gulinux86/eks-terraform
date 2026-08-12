cidr_block         = "10.1.0.0/16"
project_name       = "eks-prod"
region             = "us-east-1"
kubernetes_version = "1.35"
vpc_cni_version    = "v1.22.4-eksbuild.3"
coredns_version    = "v1.13.2-eksbuild.11"
kube_proxy_version = "v1.35.3-eksbuild.18"

# Production sizing — requires a paid AWS account (these types are not free-tier).
instance_types = ["t3.medium"]
desired_size   = 2
min_size       = 2
max_size       = 4

# Set to the prod account's CI deploy role ARN once that account exists.
cluster_admin_role_arns = ["arn:aws:iam::000000000000:role/github-actions-eks-terraform"]

tags = {
  Project     = "eks"
  Environment = "prod"
  ManagedBy   = "terraform"
}

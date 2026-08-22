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

# PLACEHOLDER — the prod AWS account does not exist yet. Once it does, bootstrap
# it with environment = "prod" and set this to that account's *deploy* role
# (github-actions-eks-deploy). The read-only plan role must NOT be listed here:
# it holds no cluster access by design (ARCHITECTURE.md §9).
cluster_admin_role_arns = ["arn:aws:iam::000000000000:role/github-actions-eks-deploy"]

tags = {
  Project     = "eks"
  Environment = "prod"
  ManagedBy   = "terraform"
}

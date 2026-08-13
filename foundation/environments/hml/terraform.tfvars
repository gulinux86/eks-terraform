cidr_block         = "10.0.0.0/16"
project_name       = "eks-hml"
region             = "us-east-1"
kubernetes_version = "1.35"
vpc_cni_version    = "v1.22.4-eksbuild.3"
coredns_version    = "v1.13.2-eksbuild.11"
kube_proxy_version = "v1.35.3-eksbuild.18"

# Free-tier-eligible node (new-account Free Plan only allows these types).
# t3.small = 2 vCPU / 2 GiB, x86_64 (matches the AL2023 x86_64 AMI).
instance_types = ["t3.small"]
desired_size   = 1
min_size       = 1
max_size       = 2

# IAM principals granted cluster-admin (the CI deploy role that runs Terraform,
# so the workload layer's kubernetes/helm providers are authorized).
cluster_admin_role_arns = ["arn:aws:iam::889384902110:role/github-actions-eks-terraform"]

tags = {
  Project     = "eks"
  Environment = "hml"
  ManagedBy   = "terraform"
}

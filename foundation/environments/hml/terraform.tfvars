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
#
# Reaching the Kubernetes API is authorized here, by an EKS Access Entry — a
# register separate from IAM. The read-only *plan* role is deliberately absent:
# it never talks to the cluster, which is why the workload plan runs with
# -refresh=false (ARCHITECTURE.md §9).
# The operator's console identity is listed for hml only. Being an AWS account
# administrator grants nothing inside Kubernetes — the two planes are separate — so
# without an entry here the console's Resources tab returns "Unauthorized". This is
# not privilege escalation: the same principal already holds AdministratorAccess and
# could create this entry by hand; putting it in code makes it reviewed and
# reproducible instead of a console click that vanishes on the next rebuild.
#
# Do NOT copy this line to prod: a human IAM user holding permanent cluster-admin is
# what an audit asks about. There, use a role assumed for a session.
cluster_admin_role_arns = [
  "arn:aws:iam::889384902110:role/github-actions-eks-deploy",
  "arn:aws:iam::889384902110:user/terra-admin",
]

tags = {
  Project     = "eks"
  Environment = "hml"
  ManagedBy   = "terraform"
}

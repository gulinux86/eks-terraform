cidr_block         = "10.0.0.0/16"
project_name       = "eks-hml"
region             = "us-east-1"
kubernetes_version = "1.35"
vpc_cni_version    = "v1.22.4-eksbuild.3"
coredns_version    = "v1.13.2-eksbuild.11"
kube_proxy_version = "v1.35.3-eksbuild.18"

# Node sizing is driven by the VPC CNI's pod-per-node cap, which comes from ENI
# capacity rather than CPU or memory:
#
#   t3.small         2 vCPU  2 GiB   3 ENIs x  4 IPs  ->  11 pods
#   m7i-flex.large   2 vCPU  8 GiB   3 ENIs x 10 IPs  ->  29 pods
#
# Both are free-tier-eligible on a new account. t3.small was the original choice
# and left the cluster artificially cramped: 11 slots per node, 6 taken by the
# cluster's own components before anything of ours ran. Installing Argo CD alone
# forced a second node.
#
# The platform ahead — Istio, Gateway API, an OTel collector, observability — needs
# roughly 32 pods. Two t3.small give 22 slots and cannot hold it; two
# m7i-flex.large give 58, with room for what comes after.
#
# Cost: m7i-flex.large is ~4.5x t3.small per hour. That is the honest price of the
# capacity, and it is why the type is set per environment rather than defaulted.
instance_types = ["m7i-flex.large"]
desired_size   = 2
min_size       = 1
max_size       = 3

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
  # The account root, because that is the identity signed into the console today
  # (terra-admin has access keys but no console login). EKS does accept root as an
  # access-entry principal — verified against the API, not assumed. Without this the
  # console's Resources and Compute tabs return Unauthorized: listing Kubernetes
  # objects goes through RBAC, where being an AWS administrator counts for nothing.
  #
  # hml only. Root cannot be scoped, restricted or attributed to a person, so this
  # is a convenience that trades away auditability — acceptable in a demo
  # environment that is destroyed between sessions, not in production. See §6/§11.
  "arn:aws:iam::889384902110:root",
]

tags = {
  Project     = "eks"
  Environment = "hml"
  ManagedBy   = "terraform"
}

# --- API endpoint exposure -------------------------------------------------
# Public access is on so Terraform can reach the API from GitHub-hosted runners.
# Stated here rather than inherited: whether the control plane answers the
# internet is not a decision that should live in a module default.
endpoint_public_access = true
public_access_cidrs    = ["0.0.0.0/0"]

# --- Control-plane log retention -------------------------------------------
log_retention_days = 90

# --- Add-on versions -------------------------------------------------------
# Every add-on is pinned. Left unset, each resolves to whatever is newest at
# apply time, so two applies months apart install different software with no
# diff in the code — the drift ARCHITECTURE.md §4 exists to prevent.
metrics_server_version     = "v0.9.0-eksbuild.6"
ebs_csi_version            = "v1.64.0-eksbuild.1"
pod_identity_agent_version = "v1.4.0-eksbuild.1"

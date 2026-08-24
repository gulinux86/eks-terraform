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

# --- API endpoint exposure -------------------------------------------------
# Public access is still required while CI runs on GitHub-hosted runners, but
# production must narrow the CIDR to known egress ranges before it carries real
# traffic. Written out explicitly so the gap is visible in review rather than
# inherited from a default — see ARCHITECTURE.md §11.
endpoint_public_access = true
public_access_cidrs    = ["0.0.0.0/0"] # TODO: office / CI egress ranges only

# --- Control-plane log retention -------------------------------------------
# Same 90 days as hml. Revisit if audit requirements or log volume argue
# otherwise; the point is that the number is chosen, not defaulted.
log_retention_days = 90

# --- Add-on versions -------------------------------------------------------
metrics_server_version     = "v0.9.0-eksbuild.6"
ebs_csi_version            = "v1.64.0-eksbuild.1"
pod_identity_agent_version = "v1.4.0-eksbuild.1"

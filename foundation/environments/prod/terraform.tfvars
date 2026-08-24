# =============================================================================
# prod — production environment
#
# NOT DEPLOYED. The AWS account does not exist yet: the principal below is a
# placeholder (000000000000), and the backend.hcl in this directory still points
# at the homologation account's state bucket. Both must be corrected before this
# environment is applied — see the open work in ARCHITECTURE.md §10.
#
# Every input is declared explicitly, including the ones identical to hml. A
# setting this consequential should be readable in the environment's own file
# rather than inferred from a default somewhere else.
# =============================================================================

# --- Identity and networking -------------------------------------------------
project_name = "eks-prod"
region       = "us-east-1"
cidr_block   = "10.1.0.0/16" # distinct from hml's 10.0/16, so the two can never route to each other

# --- Kubernetes and add-on versions ------------------------------------------
# These belong together and must move together. An add-on left behind during a
# control-plane upgrade falls out of supported version skew, surfacing as
# intermittent DNS and routing failures whose cause is hard to trace (§4).
#
# Production should lag hml deliberately: a version proves itself there first.
# Today both track 1.35 because hml is the only environment that exists.
kubernetes_version = "1.35"

vpc_cni_version            = "v1.22.4-eksbuild.3"
coredns_version            = "v1.13.2-eksbuild.11"
kube_proxy_version         = "v1.35.3-eksbuild.18"
metrics_server_version     = "v0.9.0-eksbuild.6"
ebs_csi_version            = "v1.64.0-eksbuild.1"
pod_identity_agent_version = "v1.4.0-eksbuild.1"

# --- Compute ------------------------------------------------------------------
# Not free-tier types: this environment assumes a paid account. Sized for two
# nodes minimum so a single node loss never takes the cluster with it.
instance_types = ["m7i-flex.large"]
desired_size   = 2
min_size       = 2
max_size       = 4

# --- API endpoint exposure ----------------------------------------------------
# Public access is still required while CI runs on GitHub-hosted runners, but
# production must narrow the CIDR to known egress ranges before it carries real
# traffic. Written out explicitly so the gap is visible in review rather than
# inherited — see the §11 hardening table.
endpoint_public_access = true
public_access_cidrs    = ["0.0.0.0/0"] # TODO: office / CI egress ranges only

# --- Observability ------------------------------------------------------------
# Same 90 days as hml. Revisit if audit requirements or log volume argue
# otherwise; the point is that the number is chosen, not defaulted.
log_retention_days = 90

# --- Cluster access -----------------------------------------------------------
# Only the CI deploy role. Deliberately unlike hml, which additionally lists a
# human IAM user and the account root for console convenience: a human principal
# with standing cluster-admin is an audit finding, and root cannot be scoped,
# restricted, or attributed to a person at all.
#
# Human access to production belongs to a role assumed for a session, with an
# operator console login of their own and MFA (§6, §11).
cluster_admin_role_arns = [
  "arn:aws:iam::000000000000:role/github-actions-eks-deploy", # TODO: real account id
]

# --- Tags ---------------------------------------------------------------------
tags = {
  Project     = "eks"
  Environment = "prod"
  ManagedBy   = "terraform"
}

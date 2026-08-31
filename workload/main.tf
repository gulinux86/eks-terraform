# Reads the foundation layer outputs (cluster, OIDC, endpoint, CA, tags...).
data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.foundation_state_bucket
    key    = var.foundation_state_key
    region = var.region
  }
}

module "eks_aws_load_balancer_controller" {
  source       = "./modules/aws-load-balancer-controller"
  project_name = data.terraform_remote_state.foundation.outputs.project_name
  tags         = data.terraform_remote_state.foundation.outputs.tags
  oidc         = data.terraform_remote_state.foundation.outputs.oidc
  cluster_name = data.terraform_remote_state.foundation.outputs.cluster_name
  region       = var.region
  vpc_id       = data.terraform_remote_state.foundation.outputs.vpc_id
}

# The platform's ingress edge, owned by Terraform.
#
# The load balancer, its target group and its security group are declared here so
# that `terraform destroy` holds the edge from the load balancer to the subnets it
# occupies. Previously a controller created that load balancer in response to a
# Gateway in Git, it never entered state, and its ENIs held the private subnets
# through four failed destroys (ARCHITECTURE.md §3, design §1).
#
# The cluster's only involvement is a TargetGroupBinding, which registers pod IPs
# into a target group it does not own.
module "platform_ingress" {
  source       = "./modules/platform-ingress"
  project_name = data.terraform_remote_state.foundation.outputs.project_name
  tags         = data.terraform_remote_state.foundation.outputs.tags

  vpc_id             = data.terraform_remote_state.foundation.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.foundation.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.foundation.outputs.private_subnet_ids

  gateway_namespace    = var.gateway_namespace
  gateway_service_name = var.gateway_service_name
  listener_port        = var.ingress_listener_port

  # TargetGroupBinding is the controller's CRD, so the controller has to be
  # installed before the binding can be accepted.
  depends_on = [module.eks_aws_load_balancer_controller]
}

# Argo CD. Installed last in the workload layer, which is itself the last layer
# applied — so it lands on a cluster that already has its network, nodes and
# load-balancer controller in place.
#
# It is deliberately installed and left alone: no root Application, no repository
# wired up. What it establishes is the CRDs and controllers, so that from here on
# custom resources can be delivered through Argo instead of through Terraform.
module "argocd" {
  source        = "./modules/argocd"
  tags          = data.terraform_remote_state.foundation.outputs.tags
  chart_version = var.argocd_chart_version

  # Not a dependency Terraform can infer, and not strictly required — but it keeps
  # the apply order legible: cluster add-ons first, then the GitOps controller.
  depends_on = [module.eks_aws_load_balancer_controller]
}

# Default StorageClass. The EBS CSI driver is installed by the foundation layer,
# but a driver with no StorageClass provisions nothing — see the module README.
module "storage" {
  source         = "./modules/storage"
  reclaim_policy = var.storage_reclaim_policy
}

# The handover: Terraform creates the privilege boundary and one root Application,
# then stops. Everything else reaches the cluster through Argo CD, from Git.
module "argocd_bootstrap" {
  source    = "./modules/argocd-bootstrap"
  namespace = module.argocd.namespace

  platform_repo_url      = var.platform_repo_url
  platform_repo_revision = var.platform_repo_revision
  apps_repo_url          = var.apps_repo_url
  platform_source_repos  = var.platform_source_repos
  apps_source_repos      = var.apps_source_repos
  apps_namespaces        = var.apps_namespaces

  # The projects and the root app are meaningless until Argo CD's CRDs exist.
  depends_on = [module.argocd]
}

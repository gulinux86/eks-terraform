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

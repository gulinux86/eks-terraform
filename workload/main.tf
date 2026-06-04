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

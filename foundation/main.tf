module "eks_network" {
  source       = "./modules/network"
  cidr_block   = var.cidr_block
  project_name = var.project_name
  tags         = var.tags
}

module "eks_cluster" {
  source                 = "./modules/cluster"
  project_name           = var.project_name
  tags                   = var.tags
  private_subnet_1a      = module.eks_network.subnet_private_1a
  private_subnet_1b      = module.eks_network.subnet_private_1b
  vpc_cidr               = module.eks_network.vpc_cidr
  kubernetes_version     = var.kubernetes_version
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs
  admin_role_arns        = var.cluster_admin_role_arns
}

module "eks_managed-node-group" {
  source            = "./modules/managed-node-group"
  project_name      = var.project_name
  cluster_name      = module.eks_cluster.cluster_name
  subnet_private_1a = module.eks_network.subnet_private_1a
  subnet_private_1b = module.eks_network.subnet_private_1b
  tags              = var.tags
  instance_types    = var.instance_types
  desired_size      = var.desired_size
  min_size          = var.min_size
  max_size          = var.max_size
}

module "bastion" {
  source            = "./modules/bastion"
  project_name      = var.project_name
  tags              = var.tags
  region            = var.region
  vpc_id            = module.eks_network.vpc_id
  vpc_cidr          = module.eks_network.vpc_cidr
  private_subnet_id = module.eks_network.subnet_private_1a
  cluster_name      = module.eks_cluster.cluster_name
}

module "vpc_endpoints" {
  source                  = "./modules/vpc-endpoints"
  project_name            = var.project_name
  tags                    = var.tags
  region                  = var.region
  vpc_id                  = module.eks_network.vpc_id
  vpc_cidr                = module.eks_network.vpc_cidr
  private_subnet_ids      = module.eks_network.private_subnet_ids
  private_route_table_ids = module.eks_network.private_route_table_ids
}

# Managed core add-ons. Applied after the node group so coredns has compute to
# schedule on; OVERWRITE adopts the EKS-installed defaults into IaC control.
module "eks_addons" {
  source             = "./modules/eks-addons"
  cluster_name       = module.eks_cluster.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_cni_version    = var.vpc_cni_version
  coredns_version    = var.coredns_version
  kube_proxy_version = var.kube_proxy_version
  tags               = var.tags

  depends_on = [module.eks_managed-node-group]
}

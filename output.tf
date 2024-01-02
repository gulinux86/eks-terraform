output "subnet_pub_1a" {
  value = module.eks_network.subnet_pub_1a
}

output "oidc" {
  value = module.eks_cluster.oidc
}
output "subnet_pub_1a" {
  value = module.eks_network.subnet_pub_1a
}

output "oidc" {
  value = module.eks_cluster.oidc
}
output "ca" {
  value = module.eks_cluster.certificate_authority
}

output "endpoint" {
  value = module.eks_cluster.endpoint
}
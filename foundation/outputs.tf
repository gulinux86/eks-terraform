# Consumed by the `workload` layer via terraform_remote_state, as well as by operators.

output "cluster_name" {
  value       = module.eks_cluster.cluster_name
  description = "EKS cluster name"
}

output "oidc" {
  value       = module.eks_cluster.oidc
  description = "Cluster OIDC provider issuer URL (used for IRSA)"
}

output "endpoint" {
  value       = module.eks_cluster.endpoint
  description = "Cluster API server endpoint"
  sensitive   = true
}

output "certificate_authority" {
  value       = module.eks_cluster.certificate_authority
  description = "Cluster CA (base64) for k8s/helm provider authentication"
  sensitive   = true
}

output "project_name" {
  value       = var.project_name
  description = "Project name, reused by the workload layer"
}

output "region" {
  value       = var.region
  description = "AWS region, reused by the workload layer"
}

output "tags" {
  value       = var.tags
  description = "Project tags, reused by the workload layer"
}

output "subnet_pub_1a" {
  value       = module.eks_network.subnet_pub_1a
  description = "Public subnet 1a"
}

output "vpc_id" {
  value       = module.eks_network.vpc_id
  description = "VPC ID, used by the AWS Load Balancer Controller in the workload layer"
}

output "bastion_instance_id" {
  value       = module.bastion.bastion_instance_id
  description = "Connect with: aws ssm start-session --target <id>"
}

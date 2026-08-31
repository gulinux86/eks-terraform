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

# The workload layer places the platform ingress load balancer itself, rather than
# letting a controller in the cluster create one (ARCHITECTURE.md §3). That needs
# somewhere to put it and something to scope its security group to, so both are
# re-exported here. The network module has declared them all along; this layer
# simply never passed them on.
output "private_subnet_ids" {
  value       = module.eks_network.private_subnet_ids
  description = "Private subnets the platform ingress load balancer is placed in. Internal-only: the public subnets are deliberately not offered here."
}

output "vpc_cidr" {
  value       = module.eks_network.vpc_cidr
  description = "VPC CIDR, scoping the ingress load balancer's security group while it stays internal"
}

output "bastion_instance_id" {
  value       = module.bastion.bastion_instance_id
  description = "Connect with: aws ssm start-session --target <id>"
}

output "tooling_bucket" {
  value       = module.bastion.tooling_bucket
  description = "Bucket the bastion pulls kubectl from. The deploy workflow seeds it after applying the foundation layer."
}

output "kubectl_version" {
  value       = module.bastion.kubectl_version
  description = "kubectl version the bastion expects; the deploy workflow seeds this exact build."
}

# Consumed by the platform GitOps repository's Karpenter manifests. None of these
# are secrets; they are the handful of AWS names the in-cluster objects must match.
output "karpenter_node_role_name" {
  value       = module.karpenter.node_role_name
  description = "Role name for the EC2NodeClass's `role` field"
}

output "karpenter_interruption_queue" {
  value       = module.karpenter.interruption_queue_name
  description = "Queue name for the Helm chart's settings.interruptionQueue"
}

output "karpenter_discovery_tag_value" {
  value       = module.karpenter.discovery_tag_value
  description = "Value the EC2NodeClass subnet and security-group selectors must match on karpenter.sh/discovery"
}

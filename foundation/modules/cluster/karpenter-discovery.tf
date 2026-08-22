# Karpenter selects the security group for new nodes by tag. The cluster security
# group is EKS-managed — Terraform does not create it — so the tag is applied to
# the existing resource rather than declared on it.
#
# Without this tag an EC2NodeClass finds no security group and provisions nothing,
# reporting only that the selector matched nothing.
resource "aws_ec2_tag" "cluster_sg_karpenter_discovery" {
  resource_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = aws_eks_cluster.eks_cluster.name
}

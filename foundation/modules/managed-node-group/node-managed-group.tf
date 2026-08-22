resource "aws_eks_node_group" "eks_managed_node_group" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.project_name}-management-node-group"
  node_role_arn   = aws_iam_role.eks_managed_role.arn
  instance_types  = var.instance_types
  ami_type        = var.ami_type
  subnet_ids = [
    var.subnet_private_1a,
    var.subnet_private_1b
  ]
  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-node-group"
    }
  )
  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  # Explicit rather than inherited, so the roll strategy is a reviewed choice.
  # Stated plainly: at desired_size = 1 (hml) one unavailable node is the whole
  # cluster, so this expresses intent and delivers no availability. It becomes
  # meaningful once the group has 2+ nodes and workloads carry PodDisruptionBudgets.
  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_managed_role_attachment_worker,
    aws_iam_role_policy_attachment.eks_managed_role_attachment_ecr,
    aws_iam_role_policy_attachment.eks_managed_role_attachment_cni
  ]
}

# Name tag for the worker instances.
#
# The `tags` argument above lands on the node group resource, not on the EC2
# instances — EKS tags those with eks:cluster-name / eks:nodegroup-name and no
# Name, which is why they show up blank in the console. Tagging the ASG that EKS
# created, with propagation on launch, is the light way to fix that.
#
# The alternative is a custom launch template with tag_specifications. It tags
# instances immediately rather than on next launch, but it means owning a launch
# template whose version changes can cascade into node replacement — a real
# operational edge to accept for a console label. Revisit if the module ever needs
# a launch template for its own sake (custom kubelet args, a private AMI).
#
# Consequence worth stating: propagate_at_launch only affects instances created
# after this lands. Nodes already running stay unnamed until they are replaced.
resource "aws_autoscaling_group_tag" "node_name" {
  autoscaling_group_name = aws_eks_node_group.eks_managed_node_group.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "Name"
    value               = "${var.project_name}-node"
    propagate_at_launch = true
  }
}
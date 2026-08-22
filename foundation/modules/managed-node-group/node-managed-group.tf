# Launch template carrying nothing but tags.
#
# Instance names have to be applied *at launch*, and nothing else can do it:
# `tags` on aws_eks_node_group land on the node group, and an
# aws_autoscaling_group_tag can only be created after the node group exists — by
# which point EKS has already launched the nodes. propagate_at_launch then only
# helps a future launch that, in an environment rebuilt from scratch, never comes.
# That approach was tried first and observed to leave instances unnamed.
#
# Omitting image_id is deliberate: EKS keeps supplying the EKS-optimized AMI for
# ami_type and keeps injecting the bootstrap user data. This template adds tags and
# takes over nothing.
#
# Sharp edge: a change here creates a new template version, and the node group rolls
# its nodes to adopt it. That is correct behaviour, and a reason to keep this
# template boring.
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.project_name}-node-"

  # Declaring a launch template means EKS stops supplying its own metadata
  # defaults, so they have to be restated here or the nodes silently fall back to
  # IMDSv1-permitted. These values are exactly what EKS was already applying
  # (verified against the running nodes), so this changes no behaviour — it only
  # makes the setting visible and reviewed.
  #
  # hop limit 1 is the security-relevant part: a packet from a pod on the pod
  # network needs two hops to reach IMDS, so this keeps pods away from the node's
  # instance credentials. Workloads get AWS access through IRSA instead (§7).
  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-node"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-node"
      }
    )
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-node-lt"
    }
  )
}

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
  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

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

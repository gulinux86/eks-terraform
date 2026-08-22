# The role instances launched by Karpenter assume.
#
# Deliberately separate from the managed node group's role, even though the policy
# set is identical. Keeping them apart means the system pool and Karpenter's nodes
# can diverge later — different permissions, different boundaries — without one
# change silently affecting the other.
resource "aws_iam_role" "node" {
  name        = "${var.project_name}-karpenter-node"
  description = "Role assumed by instances Karpenter provisions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    # Lets the same SSM path used for the bastion reach Karpenter's nodes, which
    # matters when a node misbehaves and there is no other way in.
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# THE STEP THAT IS EASY TO MISS.
#
# An IAM role gets an instance into the account; it does not get it into the
# cluster. Joining requires an EKS Access Entry, and for nodes it must be of type
# EC2_LINUX — not the STANDARD type used for human and CI principals elsewhere in
# this repo. EKS creates this automatically for a *managed* node group, which is
# why nothing needed it before; Karpenter's nodes are self-managed from EKS's point
# of view, so it has to be declared.
#
# Without it the instances boot, appear healthy in EC2, and never register as
# Kubernetes nodes — a failure with no obvious error to follow.
resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"

  tags = var.tags
}

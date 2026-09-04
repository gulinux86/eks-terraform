data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# The controller's role, assumed through EKS Pod Identity rather than IRSA.
#
# Pod Identity binds a role to a namespace/ServiceAccount pair from the AWS side.
# The Kubernetes object needs no annotation and therefore no role ARN — which is
# the point here: Karpenter's chart will be delivered by Argo CD from a Git
# repository, and with IRSA the ARN would have to be written into a values file,
# hardcoded per account. Pod Identity keeps that value on this side of the fence.
resource "aws_iam_role" "controller" {
  name        = "${var.project_name}-karpenter-controller"
  description = "Karpenter controller, via EKS Pod Identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

# Binds the role to exactly one ServiceAccount in one namespace. If the chart
# creates a different name, the controller gets no credentials at all — and says
# so only in its own logs.
resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.controller.arn

  tags = var.tags
}

locals {
  # Applied by the network and cluster modules to the subnets and security groups
  # Karpenter selects. Deliberately NOT used to scope instance permissions: it never
  # reaches an instance, because Karpenter reserves the karpenter.sh/ prefix and
  # drops it from an EC2NodeClass's tags without saying so.
  discovery_tag = "karpenter.sh/discovery"
}

data "aws_iam_policy_document" "controller" {
  # Reads are unscoped because Karpenter has to evaluate the whole catalogue —
  # instance types, prices, AZs, images — before it can pick anything.
  statement {
    sid       = "ReadEC2"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeAvailabilityZones",
    ]
  }

  # Creation is unscoped for the same reason a launch cannot be pre-tagged: the
  # resource does not exist yet. The condition below constrains what survives.
  statement {
    sid       = "CreateResources"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
      "ec2:RunInstances",
    ]
  }

  # Deletion is scoped by tag: Karpenter may only terminate what Karpenter made.
  # Without a condition the controller could terminate any instance in the account,
  # including the bastion and the system pool.
  #
  # The condition used to name karpenter.sh/discovery, which reads sensibly and can
  # never match. That tag is on the *subnets and security groups* Karpenter selects;
  # it is not on the instances it launches, and it cannot be put there — Karpenter
  # reserves the karpenter.sh/ prefix and drops such keys from an EC2NodeClass's
  # tags silently, with no error and no warning. So this statement authorised
  # nothing, and the controller could not terminate its own nodes.
  #
  # Two conditions now, matching the tags Karpenter actually writes and following
  # the policy AWS publishes for it:
  #
  #   kubernetes.io/cluster/<name>=owned  — the instance belongs to this cluster.
  #     On its own this is too wide: EKS puts the same tag on managed node group
  #     instances, so it would put the system pool in reach.
  #   karpenter.sh/nodepool=*             — and Karpenter launched it. This is the
  #     one that excludes the node group and the bastion.
  #
  # Both must hold. Neither is sufficient alone.
  statement {
    sid       = "TerminateOwnResources"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # Karpenter v1 manages the instance profile for its nodes itself.
  #
  # ListInstanceProfiles is not part of creating one — it is what the garbage
  # collector uses to find profiles whose nodes are gone. Without it the controller
  # logs AccessDenied on every GC pass and the profiles accumulate, unreferenced and
  # unnoticed. Found by reading the controller's logs on the first real run, not by
  # reviewing this policy.
  #
  # It is a List over the account's profiles and cannot be scoped by resource, which
  # is why it sits apart from the rest: those are writes on a profile Karpenter owns,
  # this is a read across all of them.
  statement {
    sid       = "ManageInstanceProfiles"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfiles",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
    ]
  }

  # PassRole is the dangerous one, so it names a single role. Left broad, anything
  # able to pass roles can launch an instance carrying any role in the account.
  statement {
    sid       = "PassNodeRoleOnly"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [var.cluster_arn]
  }

  # AMI ids come from SSM public parameters.
  statement {
    sid       = "ResolveAMIs"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.region}::parameter/aws/service/*"]
  }

  # Consolidation decisions need prices. The Pricing API has no VPC endpoint in
  # most regions, so this call leaves through the NAT; Karpenter falls back to a
  # built-in price list if it cannot reach it.
  statement {
    sid       = "ReadPricing"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "ConsumeInterruptionQueue"
    effect    = "Allow"
    resources = [aws_sqs_queue.interruption.arn]
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
  }
}

resource "aws_iam_role_policy" "controller" {
  name   = "${var.project_name}-karpenter-controller"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller.json
}

# Plan-mode unit tests for Karpenter's AWS-side prerequisites. Mocked provider, so
# the suite runs in CI with no credentials and creates nothing.
#
# This module hands a controller the ability to launch and terminate EC2 instances
# and to pass an IAM role to them. Three of its properties are what keep that
# bounded, and a fourth is what makes the nodes usable at all — none of them were
# guarded until this file existed, and two had already been wrong in production:
#
#   - `TerminateInstances` was conditioned on `karpenter.sh/discovery`, a tag that
#     can never reach an instance because Karpenter reserves the prefix. The
#     statement authorised nothing and the controller could not terminate its own
#     nodes. Fixed, and now asserted.
#   - `aws_cloudwatch_event_target` keyed its `for_each` on the rules resource,
#     which Terraform cannot evaluate before apply. That broke `import`, `plan` and
#     `apply` for the whole module. A plan-mode test is exactly what catches it —
#     this suite would not have loaded.
#
# See ARCHITECTURE.md §5.

mock_provider "aws" {}

variables {
  project_name = "eks-test"
  cluster_name = "eks-test-cluster"
  cluster_arn  = "arn:aws:eks:us-east-1:111122223333:cluster/eks-test-cluster"
  tags = {
    Project     = "eks"
    Environment = "test"
  }
}

# The policy's JSON is not readable at plan time — it comes from a data source the
# mocked provider computes. The statements themselves are configuration, so they are,
# and asserting on them checks the same thing one step earlier.

run "termination_is_scoped_to_karpenters_own_instances" {
  command = plan

  # Two conditions, and neither is sufficient alone.
  #
  # kubernetes.io/cluster/<name>=owned says the instance belongs to this cluster —
  # but EKS puts that same tag on managed node group instances, so on its own it
  # would put the system pool within reach. karpenter.sh/nodepool is what excludes
  # the node group and the bastion.
  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.controller.statement :
      length([
        for c in st.condition : c
        if c.variable == "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      ]) == 1
      && length([
        for c in st.condition : c
        if c.variable == "aws:ResourceTag/karpenter.sh/nodepool"
      ]) == 1
      if contains(st.actions, "ec2:TerminateInstances")
    ])
    error_message = "ec2:TerminateInstances must be conditioned on BOTH kubernetes.io/cluster/<name>=owned and karpenter.sh/nodepool; either alone lets the controller reach the system pool or authorises nothing"
  }

  # The tag that cannot work. Karpenter reserves the karpenter.sh/ prefix and drops
  # such keys from an EC2NodeClass's tags silently, so an instance never carries
  # karpenter.sh/discovery — a condition naming it matches nothing, forever.
  assert {
    condition = length([
      for st in data.aws_iam_policy_document.controller.statement :
      st
      if length([
        for c in st.condition : c
        if c.variable == "aws:ResourceTag/karpenter.sh/discovery"
      ]) > 0
    ]) == 0
    error_message = "no statement may key on aws:ResourceTag/karpenter.sh/discovery: that tag is on the subnets and security groups Karpenter selects, never on an instance"
  }
}

run "pass_role_is_bounded" {
  command = plan

  # The dangerous grant. Left unconditioned, anything able to pass roles can launch
  # an instance carrying any role in the account. The resource it names is the node
  # role's ARN, which is computed and therefore not assertable here; the condition
  # is, and it is what stops the role being handed to anything but EC2.
  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.controller.statement :
      length([
        for c in st.condition : c
        if c.variable == "iam:PassedToService"
      ]) == 1
      if contains(st.actions, "iam:PassRole")
    ])
    error_message = "iam:PassRole must be conditioned on iam:PassedToService so the role can only be handed to EC2"
  }

  # Not assertable here: the statement's `resources` is the node role's ARN, which
  # the provider computes, so a plan-mode condition touching it is unknown. The
  # scoping it provides is real and reviewed in `controller.tf`; what this suite can
  # hold is the condition above, which is the half that stops the role reaching any
  # service other than EC2.
}

run "nodes_can_actually_join_the_cluster" {
  command = plan

  # A role gets an instance into the account; joining the cluster needs an access
  # entry, and for nodes it must be EC2_LINUX rather than the STANDARD type used
  # for human and CI principals. Without it the instances boot, look healthy in
  # EC2, and never become Kubernetes nodes — with no error to follow.
  assert {
    condition     = aws_eks_access_entry.node.type == "EC2_LINUX"
    error_message = "the node role's access entry must be EC2_LINUX; STANDARD does not let an instance register as a node"
  }

  assert {
    condition     = aws_eks_access_entry.node.cluster_name == var.cluster_name
    error_message = "the access entry must be created on this cluster"
  }
}

run "controller_gets_credentials_without_an_arn_in_git" {
  command = plan

  # Pod Identity rather than IRSA, so the platform GitOps repository never carries
  # an account-specific role ARN. The association binds role to namespace and
  # ServiceAccount from the AWS side; a mismatch here delivers no credentials and
  # says so only in the controller's own logs.
  assert {
    condition     = aws_eks_pod_identity_association.controller.namespace == var.namespace
    error_message = "the Pod Identity association must bind the namespace the chart installs into"
  }
  assert {
    condition     = aws_eks_pod_identity_association.controller.service_account == var.service_account
    error_message = "the Pod Identity association must name the ServiceAccount the chart creates"
  }
  assert {
    condition     = aws_eks_pod_identity_association.controller.cluster_name == var.cluster_name
    error_message = "the association must be created on this cluster"
  }

  # The controller's role must be assumable by the Pod Identity service principal
  # rather than by IRSA's OIDC federation — that is what keeps the ARN out of Git.
  assert {
    condition     = strcontains(aws_iam_role.controller.assume_role_policy, "pods.eks.amazonaws.com")
    error_message = "the controller role must trust pods.eks.amazonaws.com; an OIDC trust would mean IRSA, and IRSA needs the ARN written into a values file"
  }
}

run "interruption_queue_is_wired_end_to_end" {
  command = plan

  # Karpenter runs fine without the queue, which is the trap: the gap only shows
  # during a Spot reclaim, when the node vanishes instead of draining.
  assert {
    condition     = length(aws_cloudwatch_event_rule.interruption) == 4
    error_message = "expected four EventBridge rules: spot interruption, rebalance, state change, scheduled change"
  }

  # One target per rule. This resource keyed its for_each on the rules themselves
  # until it broke import, plan and apply for the whole module — Terraform cannot
  # know a resource's keys before apply. Keys now come from the static local, which
  # is also why this suite can load at all.
  assert {
    condition     = length(aws_cloudwatch_event_target.interruption) == length(aws_cloudwatch_event_rule.interruption)
    error_message = "every interruption rule needs a target, or the event is raised and nothing consumes it"
  }

  assert {
    condition     = aws_sqs_queue.interruption.sqs_managed_sse_enabled == true
    error_message = "the interruption queue must be encrypted at rest"
  }
}

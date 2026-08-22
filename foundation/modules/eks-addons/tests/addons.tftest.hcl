# Plan-mode unit tests for the eks-addons module. Mocked AWS provider → no creds,
# no infra. Guards that the three core add-ons stay declared, pinned and adopted.

mock_provider "aws" {
  # A mocked data source returns a placeholder string, and the provider validates
  # that assume_role_policy is a JSON object — so the trust policy has to be given
  # a shape here. The policy's *content* is not what this suite is testing; that it
  # exists and is attached to the right add-on is.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  cluster_name       = "eks-test-cluster"
  kubernetes_version = "1.35"
  # Pin explicit versions so the test is deterministic and the addon_version
  # passes the provider's semver validation (the mocked data source returns a
  # non-semver placeholder). The version-resolution path is exercised at apply.
  vpc_cni_version            = "v1.19.2-eksbuild.1"
  coredns_version            = "v1.11.4-eksbuild.2"
  kube_proxy_version         = "v1.35.0-eksbuild.2"
  metrics_server_version     = "v0.7.2-eksbuild.1"
  ebs_csi_version            = "v1.44.0-eksbuild.1"
  pod_identity_agent_version = "v1.3.4-eksbuild.1"
  oidc_provider_arn          = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  tags = {
    Project = "eks"
  }
}

run "core_addons_managed_and_pinned" {
  command = plan

  # Every add-on the platform depends on is declared.
  assert {
    condition     = length(aws_eks_addon.this) == 6
    error_message = "expected six managed add-ons"
  }
  assert {
    condition = alltrue([
      for n in ["vpc-cni", "coredns", "kube-proxy", "metrics-server", "aws-ebs-csi-driver", "eks-pod-identity-agent"] :
      contains(keys(aws_eks_addon.this), n)
    ])
    error_message = "every add-on the platform depends on must be declared"
  }

  # The pod identity agent is the node-side half of EKS Pod Identity: without it an
  # association exists in AWS and quietly delivers no credentials to the pod.
  assert {
    condition     = contains(keys(aws_eks_addon.this), "eks-pod-identity-agent")
    error_message = "eks-pod-identity-agent must be managed, or Pod Identity associations deliver nothing"
  }

  # metrics-server is what makes HPA and `kubectl top` possible at all; its
  # absence is silent, so assert it rather than trust it.
  assert {
    condition     = contains(keys(aws_eks_addon.this), "metrics-server")
    error_message = "metrics-server must be managed: without it there is no HPA and no kubectl top"
  }

  # The EBS CSI driver is the only add-on that calls the AWS API. Without a role it
  # installs cleanly and then fails to provision any volume — PVCs simply stay
  # Pending, with nothing obviously wrong.
  #
  # The role's ARN is unknown under a mocked provider at plan time, so these assert
  # on what is knowable: that the role and its policy attachment are declared, and
  # that the attachment points at the policy AWS maintains for this driver.
  assert {
    condition     = length(aws_iam_role.ebs_csi) == 1
    error_message = "the EBS CSI driver must have an IAM role, or every PersistentVolumeClaim stays Pending"
  }
  assert {
    condition     = aws_iam_role_policy_attachment.ebs_csi[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    error_message = "use the AWS-managed EBS CSI policy; a hand-written one drifts from the driver on every upgrade"
  }

  # Each carries a resolved (non-empty) version — the whole point of managing them.
  assert {
    condition = alltrue([
      for a in aws_eks_addon.this : a.addon_version != null && a.addon_version != ""
    ])
    error_message = "every add-on must have a pinned/resolved addon_version"
  }

  # Conflict resolution is explicit so manual edits never leave the cluster drifted.
  assert {
    condition = alltrue([
      for a in aws_eks_addon.this :
      a.resolve_conflicts_on_create == "OVERWRITE" && a.resolve_conflicts_on_update == "OVERWRITE"
    ])
    error_message = "add-ons must set OVERWRITE conflict resolution on create and update"
  }
}

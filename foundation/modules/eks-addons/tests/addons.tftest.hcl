# Plan-mode unit tests for the eks-addons module. Mocked AWS provider → no creds,
# no infra. Guards that the three core add-ons stay declared, pinned and adopted.

mock_provider "aws" {}

variables {
  cluster_name       = "eks-test-cluster"
  kubernetes_version = "1.35"
  # Pin explicit versions so the test is deterministic and the addon_version
  # passes the provider's semver validation (the mocked data source returns a
  # non-semver placeholder). The version-resolution path is exercised at apply.
  vpc_cni_version    = "v1.19.2-eksbuild.1"
  coredns_version    = "v1.11.4-eksbuild.2"
  kube_proxy_version = "v1.35.0-eksbuild.2"
  tags = {
    Project = "eks"
  }
}

run "core_addons_managed_and_pinned" {
  command = plan

  # All three core add-ons are declared.
  assert {
    condition     = length(aws_eks_addon.this) == 3
    error_message = "expected exactly three managed core add-ons"
  }
  assert {
    condition = alltrue([
      for n in ["vpc-cni", "coredns", "kube-proxy"] : contains(keys(aws_eks_addon.this), n)
    ])
    error_message = "vpc-cni, coredns and kube-proxy must all be declared"
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

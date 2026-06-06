# EKS core add-ons managed as code. Left unmanaged, vpc-cni/coredns/kube-proxy run
# as self-managed add-ons at whatever version EKS shipped at cluster creation —
# which silently drifts out of supported version skew during a control-plane
# upgrade (e.g. coredns/kube-proxy left behind on a 1.34 build under a 1.35 API).
# Declaring them here makes the version a reviewed, reproducible part of every
# upgrade. See ARCHITECTURE.md §4.

# Resolve the latest add-on version compatible with the cluster's Kubernetes
# version (used unless a version is pinned explicitly via the *_version vars).
data "aws_eks_addon_version" "this" {
  for_each           = toset(["vpc-cni", "coredns", "kube-proxy"])
  addon_name         = each.key
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

locals {
  addon_versions = {
    "vpc-cni"    = var.vpc_cni_version != null ? var.vpc_cni_version : data.aws_eks_addon_version.this["vpc-cni"].version
    "coredns"    = var.coredns_version != null ? var.coredns_version : data.aws_eks_addon_version.this["coredns"].version
    "kube-proxy" = var.kube_proxy_version != null ? var.kube_proxy_version : data.aws_eks_addon_version.this["kube-proxy"].version
  }
}

resource "aws_eks_addon" "this" {
  for_each = local.addon_versions

  cluster_name  = var.cluster_name
  addon_name    = each.key
  addon_version = each.value

  # OVERWRITE so a manual kubectl edit can never leave the cluster drifted from
  # the declared add-on version/config.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

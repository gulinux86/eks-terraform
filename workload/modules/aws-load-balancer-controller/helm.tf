# Chart and IAM policy move together. Each release may call AWS APIs the previous
# one did not, and AWS publishes the matching policy per release: iam_policy.json is
# docs/install/iam_policy.json at the same tag, verbatim — 1.6.2 to 3.6.1 added ten
# actions. A chart bump without it fails at runtime with AccessDenied, not at plan.
#
# Since v3 the chart version equals the controller's (chart 1.6.2 was v2.6.2).
#
# CRDs: Helm installs the chart's crds/ on the first install only and never upgrades
# them. Every hml deploy is a fresh cluster, so that is enough here. Upgrading the
# chart on a live cluster needs the release notes' CRD step first —
# `kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=<tag>"`.
resource "helm_release" "eks_helm_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.1"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  # Explicit region and vpcId: the cluster is private and IMDS may be
  # restricted, so we do not rely on the controller's auto-discovery.
  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  # The controller's only job here is the TargetGroupBinding (ARCHITECTURE.md §7);
  # Istio is the Gateway API implementation. v3 turns its own Gateway controllers on
  # by default and then disables them only if the Gateway API CRDs are missing when
  # it starts — absent at this layer's apply, present once Argo CD syncs them — so
  # without this the same chart would behave differently after its first restart.
  set {
    name  = "controllerConfig.featureGates.ALBGatewayAPI"
    value = "false"
  }

  set {
    name  = "controllerConfig.featureGates.NLBGatewayAPI"
    value = "false"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # Ensure the service account (with the IRSA annotation) exists before the chart.
  depends_on = [kubernetes_service_account.eks_controller_sa]
}
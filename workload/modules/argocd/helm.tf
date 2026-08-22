# Argo CD, installed by the Helm provider in the workload layer.
#
# The chart brings its own CRDs (Application, ApplicationSet, AppProject). That
# ordering is the whole point: once these types exist and the controllers are
# running, Argo CD — not Terraform — applies every other CRD and custom resource
# the platform needs (Karpenter NodePools, Argo Rollouts, and so on). Terraform
# never has to apply a custom resource whose CRD does not yet exist, which is the
# plan-time chicken-and-egg that makes `kubernetes_manifest` painful for CRs.
#
# Scope: this installs Argo CD and nothing else. No root Application, no
# app-of-apps, no repository wiring. Those are deliberate follow-ups — see README.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  # CRDs ship with the chart. Helm installs them on first release but does NOT
  # upgrade CRDs on a subsequent `helm upgrade` — a well-known Helm 3 behaviour.
  # A chart bump that changes a CRD therefore needs the CRD applied out of band.
  # Verify this against the release notes when bumping chart_version.
  set {
    name  = "crds.install"
    value = "true"
  }

  # Never remove the CRDs when the release is uninstalled. Deleting them would
  # cascade-delete every Application object in the cluster.
  set {
    name  = "crds.keep"
    value = "true"
  }

  set {
    name  = "global.domain"
    value = "argocd.${var.namespace}.svc.cluster.local"
  }

  # Nothing is exposed. Reach the UI with:
  #   kubectl -n argocd port-forward svc/argocd-server 8080:443
  set {
    name  = "server.service.type"
    value = var.server_service_type
  }

  # HA multiplies the pod count (redis-ha alone is three pods). Off by default so
  # the release fits the demo node group; see the README for the sizing maths.
  set {
    name  = "redis-ha.enabled"
    value = tostring(var.ha_enabled)
  }
  set {
    name  = "controller.replicas"
    value = var.ha_enabled ? "2" : "1"
  }
  set {
    name  = "server.replicas"
    value = var.ha_enabled ? "2" : "1"
  }
  set {
    name  = "repoServer.replicas"
    value = var.ha_enabled ? "2" : "1"
  }

  # Give the release room to pull images and pass readiness on small nodes; the
  # default 5m is tight when several pods start at once on a two-node cluster.
  timeout = 900
  wait    = true
}

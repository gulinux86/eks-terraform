# The handover point: Terraform stops here and Argo CD takes over.
#
# Delivered as a local Helm chart rather than kubernetes_manifest resources. That
# provider needs a CRD's schema at *plan* time, and on a first apply Argo CD's CRDs
# do not exist yet — the plan fails before anything can create them. Helm hands
# manifests to the cluster at apply time and never asks Terraform to understand
# them, which sidesteps the problem entirely.
#
# What Terraform keeps: the AppProjects. They are the privilege boundary between
# platform and applications, and a boundary stored in the repository it governs can
# be widened by anyone who can commit to that repository.
resource "helm_release" "bootstrap" {
  name      = "argocd-bootstrap"
  chart     = "${path.module}/chart"
  namespace = var.namespace

  set {
    name  = "platformRepoUrl"
    value = var.platform_repo_url
  }
  set {
    name  = "platformRepoRevision"
    value = var.platform_repo_revision
  }
  set {
    name  = "appsRepoUrl"
    value = var.apps_repo_url
  }
  set {
    name  = "appsNamespaces"
    value = "{${join(",", var.apps_namespaces)}}"
  }

  # The root Application references the platform project, so the project has to
  # exist first. Helm sorts unknown kinds alphabetically and AppProject precedes
  # Application, which gets the ordering right — and if it ever did not, Argo CD
  # reports "project not found" and reconciles once the project appears.
  wait    = true
  timeout = 300
}

output "namespace" {
  value       = helm_release.argocd.namespace
  description = "Namespace Argo CD runs in"
}

output "chart_version" {
  value       = helm_release.argocd.version
  description = "Installed argo-cd chart version"
}

output "port_forward_command" {
  value       = "kubectl -n ${helm_release.argocd.namespace} port-forward svc/argocd-server 8080:443"
  description = "Nothing is exposed; reach the UI through this port-forward, then https://localhost:8080"
}

output "initial_password_command" {
  value       = "kubectl -n ${helm_release.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "Retrieves the generated admin password. Change it and delete the secret; it is a bootstrap credential, not a permanent one."
}

variable "tags" {
  type        = map(string)
  description = "Tags to be added to AWS resources"
}

variable "namespace" {
  type        = string
  description = "Namespace Argo CD is installed into. Kept separate from kube-system so its RBAC and resource footprint are isolated from the cluster's own components."
  default     = "argocd"
}

variable "chart_version" {
  type        = string
  description = "argo-cd Helm chart version. Pinned deliberately: an unpinned chart means a rebuild can silently install a different Argo CD than the one that was reviewed. Chart 10.4.0 ships Argo CD v3.5.1."
  default     = "10.4.0"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.chart_version))
    error_message = "chart_version must be an exact semantic version like \"10.4.0\" — no ranges, no \"latest\"."
  }
}

variable "ha_enabled" {
  type        = bool
  description = "Run Argo CD in high-availability mode. Off by default: HA adds a redis-ha cluster (3 pods) plus extra replicas, which does not fit a two-node t3.small cluster. Turn on when the node group can carry it."
  default     = false
}

variable "server_service_type" {
  type        = string
  description = "Kubernetes Service type for the Argo CD API/UI server. ClusterIP by default — nothing is exposed and access is via `kubectl port-forward`. Exposing the UI is a separate, deliberate change: it needs an ingress, TLS and an authentication story."
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.server_service_type)
    error_message = "server_service_type must be ClusterIP, NodePort or LoadBalancer."
  }
}

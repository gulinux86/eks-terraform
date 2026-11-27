variable "region" {
  type        = string
  description = "AWS region (must match the foundation layer region)"
}

variable "foundation_state_bucket" {
  type        = string
  description = "S3 bucket holding the foundation layer state"
}

variable "foundation_state_key" {
  type        = string
  description = "Foundation layer state key (e.g. foundation/hml/terraform.tfstate)"
}

variable "argocd_chart_version" {
  type        = string
  description = "argo-cd Helm chart version. Chart 10.4.0 ships Argo CD v3.5.1."
}

variable "storage_reclaim_policy" {
  type        = string
  description = "Reclaim policy for the default StorageClass. Retain protects data; Delete prevents orphaned volumes accruing cost in an environment that is rebuilt often."
}

variable "platform_repo_url" {
  type        = string
  description = "Git repository holding platform components. The platform AppProject accepts sources only from here."
}

variable "platform_repo_revision" {
  type        = string
  description = "Branch or tag the root Application tracks. A branch follows every commit; a tag makes promotion explicit."
}

variable "apps_repo_url" {
  type        = string
  description = "Git repository that will hold applications. Declared before the repository exists so the privilege boundary is reviewed before there is pressure to bend it."
}

variable "apps_namespaces" {
  type        = list(string)
  description = "Namespace patterns the apps project may deploy into. A prefix glob such as [\"app-*\"] avoids a Terraform change per application while keeping kube-system, istio-system, argocd and cert-manager unreachable."
}

variable "platform_source_repos" {
  type        = list(string)
  description = "Repositories the platform project may source from, chart repositories included. Enumerated rather than \"*\" so a component cannot be installed from an arbitrary registry."
}

variable "apps_source_repos" {
  type        = list(string)
  description = "Repositories the apps project may source from, chart repositories included."
}

# --- Platform ingress ---------------------------------------------------------
# The one contract that points from Terraform out to the GitOps repository. Every
# other cross-layer reference in this codebase flows the other way, so these are
# declared without defaults: a wrong value here is silent (the target group simply
# registers nothing), and a default would make it silent *and* invisible.
variable "gateway_namespace" {
  type        = string
  description = "Namespace of the Service istiod generates for the platform Gateway. Must match the Gateway's namespace in the platform GitOps repository."
}

variable "gateway_service_name" {
  type        = string
  description = "Name of that Service. Istio derives it from the Gateway's name, so renaming the Gateway in Git requires changing this value in the same change."
}

variable "ingress_listener_port" {
  type        = number
  description = "Port the platform ingress load balancer listens on, and the Gateway Service port it forwards to."
}

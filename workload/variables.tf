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
  default     = "10.4.0"
}

variable "storage_reclaim_policy" {
  type        = string
  description = "Reclaim policy for the default StorageClass. Retain protects data; Delete prevents orphaned volumes accruing cost in an environment that is rebuilt often."
  default     = "Retain"
}

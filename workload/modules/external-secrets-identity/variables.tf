variable "project_name" {
  type        = string
  description = "Prefix of the role name."
}

variable "tags" {
  type        = map(string)
  description = "Tags to be added to AWS resources"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster the Pod Identity association is created in."
}

variable "namespace" {
  type        = string
  description = "Namespace the External Secrets Operator runs in. Must match the Application's destination in platform-gitops (apps/01-external-secrets.yaml)."
  default     = "external-secrets"
}

variable "service_account" {
  type        = string
  description = "The controller's ServiceAccount. Must match serviceAccount.name in platform-gitops (components/external-secrets/values.yaml)."
  default     = "external-secrets"
}

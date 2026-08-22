variable "project_name" {
  type        = string
  description = "Project name used to name the resources"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster Karpenter provisions nodes for"
}

variable "cluster_arn" {
  type        = string
  description = "Cluster ARN, so the controller's eks:DescribeCluster grant is scoped to this cluster only"
}

variable "namespace" {
  type        = string
  description = "Namespace the Karpenter controller runs in. Karpenter v1 charts default to kube-system."
  default     = "kube-system"
}

variable "service_account" {
  type        = string
  description = "Karpenter's ServiceAccount name. The Pod Identity association binds the role to this namespace/name pair, so it must match what the chart creates — a mismatch fails silently, with the controller simply unable to call AWS."
  default     = "karpenter"
}

variable "tags" {
  type        = map(string)
  description = "Tags to be added to AWS resources"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name to attach the core add-ons to"
}

variable "kubernetes_version" {
  type        = string
  description = "Cluster Kubernetes version, used to resolve a compatible add-on version"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the add-ons"
}

variable "vpc_cni_version" {
  type        = string
  description = "Pin the vpc-cni add-on version. Null resolves the latest compatible with kubernetes_version."
  default     = null
}

variable "coredns_version" {
  type        = string
  description = "Pin the coredns add-on version. Null resolves the latest compatible with kubernetes_version."
  default     = null
}

variable "kube_proxy_version" {
  type        = string
  description = "Pin the kube-proxy add-on version. Null resolves the latest compatible with kubernetes_version."
  default     = null
}

variable "metrics_server_version" {
  type        = string
  description = "Pin the metrics-server add-on version. Null resolves the latest compatible with kubernetes_version."
  default     = null
}

variable "ebs_csi_version" {
  type        = string
  description = "Pin the aws-ebs-csi-driver add-on version. Null resolves the latest compatible with kubernetes_version."
  default     = null
}

variable "oidc_provider_arn" {
  type        = string
  description = "Cluster OIDC provider ARN, used to build the EBS CSI driver's IRSA trust policy."
}

variable "enable_ebs_csi" {
  type        = bool
  description = "Create the EBS CSI driver add-on and its IAM role. On by default: without it no PersistentVolumeClaim can ever bind."
  default     = true
}

variable "pod_identity_agent_version" {
  type        = string
  description = "Pin the eks-pod-identity-agent add-on version. Null resolves the latest compatible with kubernetes_version."
  default     = null
}

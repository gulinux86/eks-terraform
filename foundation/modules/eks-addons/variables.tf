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

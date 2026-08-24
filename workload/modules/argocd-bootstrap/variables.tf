variable "namespace" {
  type        = string
  description = "Namespace Argo CD runs in. The projects and the root Application are created here."
}

variable "platform_repo_url" {
  type        = string
  description = "Git repository holding platform components. The platform AppProject accepts sources only from here."
}

variable "platform_repo_revision" {
  type        = string
  description = "Branch or tag the root Application tracks. A branch means Argo follows every commit; a tag means promotions are explicit."
}

variable "apps_repo_url" {
  type        = string
  description = "Git repository that will hold applications. The apps AppProject is created ahead of the repository existing, so the privilege boundary is written and reviewed before there is pressure to bend it."
}

variable "apps_namespaces" {
  type        = list(string)
  description = "Namespace patterns the apps project may deploy into. A prefix glob such as [\"app-*\"] avoids a Terraform change per application while keeping kube-system, istio-system, argocd and cert-manager out of reach — they do not match the prefix."
}

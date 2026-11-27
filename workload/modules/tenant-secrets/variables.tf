variable "project_name" {
  type        = string
  description = "Prefix of every role name. platform-gitops builds the same name (tenants/values.yaml, secretsRolePrefix) to reference the role from the tenant's ServiceAccount."
}

variable "tags" {
  type        = map(string)
  description = "Tags to be added to AWS resources"
}

variable "oidc" {
  type        = string
  description = "The cluster's OIDC issuer URL (foundation output `oidc`), which the roles' trust policies federate with."
}

variable "tenants" {
  type        = list(string)
  description = "Names of the tenants with `secrets: true` in platform-gitops (tenants/registry/<name>.yaml). One role each."

  validation {
    condition     = alltrue([for t in var.tenants : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", t))])
    error_message = "tenant names are lowercase letters, digits and hyphens: the same rule platform-gitops' tenant chart enforces."
  }
}

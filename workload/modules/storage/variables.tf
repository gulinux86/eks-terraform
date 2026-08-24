variable "reclaim_policy" {
  type        = string
  description = "What happens to the EBS volume when its PVC is deleted. Retain keeps it — data survives an accidental delete, but the volume is orphaned in Released state and Terraform will not clean it up, so it outlives `terraform destroy` and keeps costing. Delete removes it with the claim. Per environment on purpose: an ephemeral demo and a production cluster want opposite answers."
  default     = "Retain"

  validation {
    condition     = contains(["Retain", "Delete"], var.reclaim_policy)
    error_message = "reclaim_policy must be \"Retain\" or \"Delete\"."
  }
}

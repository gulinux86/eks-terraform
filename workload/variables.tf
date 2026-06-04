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

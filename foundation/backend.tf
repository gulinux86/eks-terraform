terraform {
  # Partial configuration: bucket/key/region come from
  # environments/<env>/backend.hcl via `terraform init -backend-config=...`.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

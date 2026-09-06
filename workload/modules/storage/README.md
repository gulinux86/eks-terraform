# storage — default StorageClass for the EBS CSI driver

The driver itself is an EKS add-on managed in the `foundation` layer. This module
supplies the piece that makes it reachable: a `gp3` StorageClass marked default,
using the CSI provisioner.

Without it, storage looks installed and does nothing. EKS's built-in `gp2` class
uses the in-tree provisioner (removed in Kubernetes 1.27) and is not marked
default, so a PVC with no explicit class stays `Pending` reporting
"no storage class is set".

It lives in `workload` because that is the only layer with the `kubernetes`
provider — see ARCHITECTURE.md §2.
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_storage_class_v1.gp3](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_reclaim_policy"></a> [reclaim\_policy](#input\_reclaim\_policy) | What happens to the EBS volume when its PVC is deleted. Retain keeps it — data survives an accidental delete, but the volume is orphaned in Released state and Terraform will not clean it up, so it outlives `terraform destroy` and keeps costing. Delete removes it with the claim. Per environment on purpose: an ephemeral demo and a production cluster want opposite answers. | `string` | `"Retain"` | no |

## Outputs

No outputs.

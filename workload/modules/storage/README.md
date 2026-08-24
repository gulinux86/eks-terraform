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

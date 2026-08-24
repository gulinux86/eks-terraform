# The StorageClass that makes the EBS CSI driver usable.
#
# Installing the driver is not enough on its own. EKS ships a `gp2` StorageClass
# whose provisioner is `kubernetes.io/aws-ebs` — the in-tree provisioner, removed
# from Kubernetes in 1.27 — and it is not marked default. So a PVC without an
# explicit storageClassName gets no class at all and stays Pending reporting
# "no storage class is set", while the CSI driver sits there healthy and unused.
#
# gp3 rather than gp2: cheaper per GB, and its baseline throughput and IOPS do not
# scale with volume size, so a small volume is not also a slow one.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"

  # EBS volumes live in a single AZ. Binding late lets the scheduler place the pod
  # first and then create the volume where the pod actually landed; binding
  # immediately can strand a pod that cannot be scheduled beside its disk.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

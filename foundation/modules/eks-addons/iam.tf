# IRSA role for the EBS CSI driver.
#
# It is the only add-on here that talks to the AWS API — it creates, attaches and
# deletes EBS volumes on behalf of PersistentVolumeClaims. The others run entirely
# inside the cluster and need nothing.
#
# IRSA rather than EKS Pod Identity, deliberately: it matches the pattern the ALB
# Controller already uses in this repo, the add-on exposes `service_account_role_arn`
# for exactly this, and it is the most-trodden path. Pod Identity is the direction
# for new roles — it removes the role ARN from the Kubernetes side entirely, which
# matters once manifests move to GitOps — and migrating this one later is a small,
# contained change.
data "aws_iam_policy_document" "ebs_csi_trust" {
  count = var.enable_ebs_csi ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Scoped to one service account in one namespace. A broader condition would
    # let any pod that can mint an OIDC token assume this role.
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^.*oidc-provider//", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^.*oidc-provider//", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  name               = "${var.cluster_name}-ebs-csi"
  description        = "IRSA role for the EBS CSI driver add-on"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust[0].json

  tags = var.tags
}

# AWS publishes a managed policy sized to exactly what the driver does. A
# hand-written policy here would drift from the driver's needs on every upgrade.
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

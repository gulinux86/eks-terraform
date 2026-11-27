# The External Secrets Operator's AWS identity: one role, bound through EKS Pod
# Identity to the controller's ServiceAccount, reading every application's secrets
# under apps/ and nothing else.
#
# One role for the whole platform rather than one per application, so that admitting
# an application is a change in Git and never a Terraform apply. The price is where
# tenants are kept apart: this role can read any application's prefix, so isolation
# between them is enforced by the API server instead of by IAM — platform-gitops'
# components/policies/tenant-secrets.yaml admits an ExternalSecret in app-<name>
# only if every key it names is under apps/<name>/, and refuses SecretStores,
# PushSecrets and generators in application namespaces (each of those would act with
# this role's credentials).
#
# Pod Identity rather than IRSA for the reason given in foundation's karpenter module:
# the binding lives on the AWS side, so the chart in Git carries no role ARN, and no
# account ID.

resource "aws_iam_role" "controller" {
  name        = "${var.project_name}-external-secrets"
  description = "External Secrets Operator controller, via EKS Pod Identity: reads apps/* in Secrets Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

# Binds the role to exactly one ServiceAccount. platform-gitops pins the chart's
# ServiceAccount name (components/external-secrets/values.yaml); if the two drift, the
# controller has no credentials and every ExternalSecret reports it.
#
# The Pod Identity webhook injects credentials when a pod is created: controller pods
# that started before this association existed keep running without them until they
# are restarted. On a fresh cluster this is applied before Argo CD installs the
# operator (workload/main.tf orders it before the bootstrap).
resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.controller.arn

  tags = var.tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Read, not list: an ExternalSecret names its keys, so ListSecrets (which cannot be
# scoped to a prefix) is not needed. The admission policy refuses `dataFrom.find`,
# the only feature that would use it.
#
# No kms:Decrypt: secrets encrypted with the account's default aws/secretsmanager key
# are decrypted by the service for any principal allowed GetSecretValue. A secret
# under a customer-managed key needs that key's policy to admit this role as well.
resource "aws_iam_role_policy" "read_app_secrets" {
  name = "read-apps-secrets"
  role = aws_iam_role.controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      # Secrets Manager appends a random six-character suffix to every secret's ARN;
      # the wildcard covers it. Platform components keep their secrets outside apps/.
      Resource = "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:apps/*"
    }]
  })
}

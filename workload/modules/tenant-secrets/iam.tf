# One IAM role per tenant, for the External Secrets Operator to read that tenant's
# secrets with — and nothing else.
#
# The operator in platform-gitops holds no AWS permissions. Each tenant's
# SecretStore presents a token for the ServiceAccount app-<name>/external-secrets
# and assumes this role with it. Two conditions make that the only way in:
#
#   - trust: `sub` must be exactly that ServiceAccount. The apps AppProject lets an
#     application create its own SecretStore, so one naming another tenant's role is
#     possible — and is refused here, because its token is for the wrong namespace.
#   - policy: read only secrets under apps/<name>/. A tenant that asks for another
#     application's path gets AccessDenied, whatever its ExternalSecret says.
#
# The role name is the contract with platform-gitops, which builds the same name to
# put the ARN on the ServiceAccount: <project_name>-app-<name>-secrets.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # https://oidc.eks.<region>.amazonaws.com/id/<id> -> the provider's host path,
  # which is both its ARN suffix and the prefix of its condition keys.
  issuer = trimprefix(var.oidc, "https://")
}

resource "aws_iam_role" "secrets" {
  for_each = toset(var.tenants)

  name = "${var.project_name}-app-${each.key}-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.issuer}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.issuer}:sub" = "system:serviceaccount:app-${each.key}:external-secrets"
          "${local.issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name   = "${var.project_name}-app-${each.key}-secrets"
    Tenant = each.key
  })
}

# Read, not list: an ExternalSecret names its keys, so ListSecrets (which cannot be
# scoped to a prefix) is not needed, and leaving it out means a tenant cannot even
# enumerate what other applications store.
#
# No kms:Decrypt: secrets encrypted with the account's default aws/secretsmanager key
# are decrypted by the service for any principal allowed GetSecretValue. A secret
# under a customer-managed key needs that key's policy to admit this role as well.
resource "aws_iam_role_policy" "read_own_secrets" {
  for_each = aws_iam_role.secrets

  name = "read-apps-${each.key}"
  role = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      # Secrets Manager appends a random six-character suffix to every secret's ARN,
      # hence the trailing wildcard after the prefix.
      Resource = "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:apps/${each.key}/*"
    }]
  })
}

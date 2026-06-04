locals {
  # OIDC subjects allowed to assume the role. The wildcard covers both the
  # plan job (which runs without a GitHub Environment) and the deploy job
  # (which sets `environment: hml|prod`). Tighten per need, e.g.
  # "repo:${var.github_repository}:environment:hml".
  allowed_subs = ["repo:${var.github_repository}:*"]
}

# Fetches GitHub's OIDC TLS certificate so we never hardcode a thumbprint.
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# Account-level OIDC identity provider for GitHub Actions. Only one per account
# per URL — if it already exists, import it instead of recreating.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.github_actions.certificates[*].sha1_fingerprint
}

# Role assumed by the CI workflows. No static keys: trust is established by the
# OIDC token, scoped to this repository, requesting the sts.amazonaws.com audience.
resource "aws_iam_role" "github_actions" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.allowed_subs
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.github_actions.name
  policy_arn = var.policy_arn
}

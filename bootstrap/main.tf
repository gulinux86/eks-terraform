locals {
  # DEPRECATED — trust of the legacy single role. The wildcard accepts every
  # workflow context, so the pull-request plan job assumed the same role that can
  # delete the account. Kept only as the cutover fallback; removed with the role.
  allowed_subs = ["repo:${var.github_repository}:*"]

  # GitHub stamps a `sub` claim describing how a run was triggered. Splitting the
  # trust on that claim is what separates readers from writers:
  #
  #   pull_request / ref:refs/heads/*  → plan job, no GitHub Environment declared
  #   environment:<name>               → deploy & destroy jobs, which declare one
  #
  # Only a job that declares an Environment can produce the second form, and the
  # Environment's deployment-branch policy decides whether such a job may start at
  # all. That policy lives in repository settings and is load-bearing: without it a
  # branch could declare the Environment and mint the deploy claim itself.
  plan_subs = [
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:ref:refs/heads/*",
  ]

  deploy_subs = ["repo:${var.github_repository}:environment:${var.environment}"]
}

# Trust policy shared in shape by both roles — only the accepted subjects differ.
data "aws_iam_policy_document" "github_actions_trust" {
  for_each = {
    plan   = local.plan_subs
    deploy = local.deploy_subs
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
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

# ---------------------------------------------------------------------------
# Plan role — assumed by terraform-plan. Read-only.
#
# It holds no write permission at all, not even Terraform's S3 state lock: the
# plan workflow passes -lock=false, since plan mutates nothing. It also holds no
# EKS Access Entry, so it cannot reach the Kubernetes API — which is why the
# workload plan runs with -refresh=false. See ARCHITECTURE.md §9.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "plan" {
  name               = var.plan_role_name
  description        = "Read-only role for terraform-plan (pull requests and branch dispatch)"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust["plan"].json
}

resource "aws_iam_role_policy_attachment" "plan" {
  role       = aws_iam_role.plan.name
  policy_arn = var.plan_policy_arn
}

# ReadOnlyAccess grants kms:Describe*/Get*/List* but NOT kms:Decrypt, so reading
# the CMK-encrypted state fails without this. A confusing failure to diagnose:
# the S3 GetObject succeeds and the decrypt is what is denied.
data "aws_iam_policy_document" "plan_state_read" {
  statement {
    sid       = "DecryptRemoteState"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "plan_state_read" {
  name   = "${var.plan_role_name}-state-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state_read.json
}

# ---------------------------------------------------------------------------
# Deploy role — assumed by terraform-deploy and terraform-destroy. Write-capable.
#
# Reachable only through a job that declares a GitHub Environment, which a pull
# request cannot do while the Environment restricts deployments to the default
# branch. Still carries a broad managed policy — a known, recorded gap.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "deploy" {
  name               = var.deploy_role_name
  description        = "Write-capable role for terraform-deploy/destroy, restricted to the ${var.environment} GitHub Environment"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust["deploy"].json
}

resource "aws_iam_role_policy_attachment" "deploy" {
  role       = aws_iam_role.deploy.name
  policy_arn = var.deploy_policy_arn
}

# ---------------------------------------------------------------------------
# Container images: the roles application pipelines push to ECR with, and the role
# app-gitops' CI reads them with.
#
# In bootstrap, not foundation or workload: images must outlive the cluster. The
# repositories are created by the pipeline on its first push (ci-templates,
# service-release.yml), not by Terraform, so `terraform-destroy` never touches them
# and the digests app-gitops pins still resolve after the cluster is rebuilt.
#
# Every repository lives under apps/ — apps/<app> or apps/<app>/<service> — and both
# roles are confined to that prefix.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  ecr_apps_arn = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/apps/*"
}

# Push: assumed by an application repository's release workflow, from its default
# branch only. A pull request builds and scans but never pushes, so it never holds
# this credential — a branch cannot publish an image that a digest PR could pick up.
data "aws_iam_policy_document" "ecr_push_trust" {
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
      values   = [for repo in var.ecr_push_repositories : "repo:${repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "ecr_push" {
  name               = var.ecr_push_role_name
  description        = "Application release workflows: create apps/* ECR repositories and push images, from main only"
  assume_role_policy = data.aws_iam_policy_document.ecr_push_trust.json
}

# No delete of any kind: a pushed image may be what a running Deployment pins, and
# removing images is the repository's lifecycle policy's job, set when the pipeline
# creates it. Tags are immutable (also set at creation), so a push cannot replace
# what a digest already points at.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "Login"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "CreateAppRepositories"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:PutLifecyclePolicy",
      "ecr:TagResource",
    ]
    resources = [local.ecr_apps_arn]
  }

  statement {
    sid    = "PushAndInspect"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [local.ecr_apps_arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "${var.ecr_push_role_name}-apps"
  role   = aws_iam_role.ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# Read: assumed by app-gitops' CI, which reads every image a values file pins —
# that it exists, and which user it runs as (scripts/ci/check.py --registry). Pull
# requests included: that is where a wrong digest has to be caught.
data "aws_iam_policy_document" "ecr_read_trust" {
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
      values = [
        "repo:${var.gitops_repository}:pull_request",
        "repo:${var.gitops_repository}:ref:refs/heads/*",
      ]
    }
  }
}

resource "aws_iam_role" "ecr_read" {
  name               = var.ecr_read_role_name
  description        = "app-gitops CI: read apps/* images to check what values files pin"
  assume_role_policy = data.aws_iam_policy_document.ecr_read_trust.json
}

data "aws_iam_policy_document" "ecr_read" {
  statement {
    sid       = "Login"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "Read"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [local.ecr_apps_arn]
  }
}

resource "aws_iam_role_policy" "ecr_read" {
  name   = "${var.ecr_read_role_name}-apps"
  role   = aws_iam_role.ecr_read.id
  policy = data.aws_iam_policy_document.ecr_read.json
}

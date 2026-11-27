# Plan-mode unit tests for the External Secrets Operator's identity. Mocked AWS
# provider, so the suite runs in CI with no credentials and creates nothing.
#
# What it guards is the ceiling on what any application can read: this role is what
# every ExternalSecret in the cluster is served with. Widening the resource past
# apps/*, or granting ListSecrets, passes fmt, validate and Trivy.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
}

variables {
  project_name = "eks-test"
  cluster_name = "eks-test"
  tags = {
    Project = "eks"
  }
}

run "bound_to_the_controllers_service_account_only" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.controller.namespace == "external-secrets" && aws_eks_pod_identity_association.controller.service_account == "external-secrets"
    error_message = "the association must name the namespace and ServiceAccount platform-gitops installs the operator with"
  }

  assert {
    condition     = jsondecode(aws_iam_role.controller.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "the role is assumed through EKS Pod Identity, not IRSA"
  }
}

run "reads_only_application_secrets" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role_policy.read_app_secrets.policy).Statement[0].Resource == (
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:apps/*"
    )
    error_message = "the operator must read only apps/*: platform secrets live outside that prefix"
  }

  assert {
    condition     = !contains(jsondecode(aws_iam_role_policy.read_app_secrets.policy).Statement[0].Action, "secretsmanager:ListSecrets")
    error_message = "ListSecrets cannot be scoped to a prefix; granting it lets any application enumerate every secret in the account"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.read_app_secrets.policy).Statement[0].Action) == 2
    error_message = "read only: GetSecretValue and DescribeSecret — the operator never writes (PushSecret is refused in application namespaces)"
  }
}

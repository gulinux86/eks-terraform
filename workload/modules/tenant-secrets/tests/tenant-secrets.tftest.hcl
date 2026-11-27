# Plan-mode unit tests for the per-tenant secrets roles. Mocked AWS provider, so the
# suite runs in CI with no credentials and creates nothing.
#
# What it guards is the isolation between tenants, which lives entirely in these two
# documents: the External Secrets Operator has no AWS identity of its own, and an
# application may write its own SecretStore. Loosening either condition — trusting a
# wildcard ServiceAccount, or a wider secret path — passes fmt, validate and Trivy.

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
  oidc         = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  tenants      = ["sim", "orders"]
  tags = {
    Project = "eks"
  }
}

run "one_role_per_tenant_named_as_platform_gitops_expects" {
  command = plan

  assert {
    condition     = aws_iam_role.secrets["sim"].name == "eks-test-app-sim-secrets"
    error_message = "the role name is the contract with platform-gitops' tenants chart: <project>-app-<name>-secrets"
  }

  assert {
    condition     = length(aws_iam_role.secrets) == 2
    error_message = "one role per tenant listed"
  }
}

run "trusts_only_the_tenants_own_service_account" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.secrets["sim"].assume_role_policy).Statement[0].Condition.StringEquals[
      "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub"
    ] == "system:serviceaccount:app-sim:external-secrets"
    error_message = "the role must trust exactly app-<name>/external-secrets, or another namespace's SecretStore could assume it"
  }

  assert {
    condition = jsondecode(aws_iam_role.secrets["sim"].assume_role_policy).Statement[0].Principal.Federated == (
      "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
    )
    error_message = "the role must federate with the cluster's own OIDC provider"
  }
}

run "reads_only_its_own_prefix" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role_policy.read_own_secrets["orders"].policy).Statement[0].Resource == (
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:apps/orders/*"
    )
    error_message = "a tenant's role must read only apps/<name>/*"
  }

  assert {
    condition     = !contains(jsondecode(aws_iam_role_policy.read_own_secrets["orders"].policy).Statement[0].Action, "secretsmanager:ListSecrets")
    error_message = "ListSecrets cannot be scoped to a prefix; granting it lets a tenant enumerate every application's secrets"
  }
}

run "rejects_an_invalid_tenant_name" {
  command = plan

  variables {
    tenants = ["Orders"]
  }

  expect_failures = [var.tenants]
}

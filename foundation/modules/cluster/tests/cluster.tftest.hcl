# Plan-mode unit tests for the cluster module. Mocked AWS/TLS providers keep the
# suite credential-free and infra-free. Guards the secure control-plane defaults
# and the admin access-entry contract.

mock_provider "aws" {}
mock_provider "tls" {}

variables {
  project_name      = "eks-test"
  private_subnet_1a = "subnet-aaaa1111"
  private_subnet_1b = "subnet-bbbb2222"
  vpc_cidr          = "10.0.0.0/16"
  admin_role_arns = [
    "arn:aws:iam::111111111111:role/ci-deploy",
    "arn:aws:iam::111111111111:user/operator",
  ]
  tags = {
    Project     = "eks"
    Environment = "test"
  }
}

run "secure_defaults_and_access_entries" {
  command = plan

  # Private API endpoint stays on regardless of public exposure.
  assert {
    condition     = aws_eks_cluster.eks_cluster.vpc_config[0].endpoint_private_access == true
    error_message = "EKS endpoint_private_access must be true"
  }

  # Modern access entries while keeping aws-auth compatibility.
  assert {
    condition     = aws_eks_cluster.eks_cluster.access_config[0].authentication_mode == "API_AND_CONFIG_MAP"
    error_message = "authentication_mode must be API_AND_CONFIG_MAP"
  }

  # Secrets envelope encryption is configured with a KMS key.
  assert {
    condition     = contains(aws_eks_cluster.eks_cluster.encryption_config[0].resources, "secrets")
    error_message = "encryption_config must cover the 'secrets' resource"
  }
  assert {
    condition     = length(aws_eks_cluster.eks_cluster.encryption_config) == 1
    error_message = "exactly one encryption_config block expected"
  }

  # One access entry + one admin policy association per admin principal.
  assert {
    condition     = length(aws_eks_access_entry.admin) == 2
    error_message = "expected one access entry per admin_role_arns entry"
  }
  assert {
    condition     = length(aws_eks_access_policy_association.admin) == 2
    error_message = "expected one admin policy association per admin_role_arns entry"
  }
  assert {
    condition = alltrue([
      for a in values(aws_eks_access_policy_association.admin) :
      a.policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    ])
    error_message = "admin associations must use AmazonEKSClusterAdminPolicy"
  }
}

# Plan-mode unit tests for the managed-node-group module. Mocked AWS provider → no
# creds, no infra. Guards that the system pool follows the cluster's version: without
# `version`, a control-plane upgrade left these nodes a minor behind with no diff in
# any plan (ARCHITECTURE.md §13).

mock_provider "aws" {
  # The node role's trust policy is rendered by a data source; the provider checks
  # it is a JSON object, so the mock has to return one.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  project_name       = "eks-test"
  cluster_name       = "eks-test-cluster"
  kubernetes_version = "1.35"
  subnet_private_1a  = "subnet-0aaaaaaaaaaaaaaaa"
  subnet_private_1b  = "subnet-0bbbbbbbbbbbbbbbb"
  instance_types     = ["m7i-flex.large"]
  tags = {
    Project = "eks"
  }
}

run "nodes_follow_the_cluster_version" {
  command = plan

  assert {
    condition     = aws_eks_node_group.eks_managed_node_group.version == "1.35"
    error_message = "the node group must take kubernetes_version, or a control-plane upgrade leaves it behind"
  }
}

run "an_upgrade_moves_the_nodes" {
  command = plan

  variables {
    kubernetes_version = "1.36"
  }

  assert {
    condition     = aws_eks_node_group.eks_managed_node_group.version == "1.36"
    error_message = "bumping kubernetes_version must move the node group with it"
  }

  # The roll EKS performs on a version change: one node out at a time, so the
  # surge-then-drain sequence never takes the whole pool down.
  assert {
    condition     = aws_eks_node_group.eks_managed_node_group.update_config[0].max_unavailable == 1
    error_message = "the node group must roll one node at a time"
  }
}

run "rejects_a_patch_version" {
  command = plan

  variables {
    kubernetes_version = "1.35.2"
  }

  expect_failures = [var.kubernetes_version]
}

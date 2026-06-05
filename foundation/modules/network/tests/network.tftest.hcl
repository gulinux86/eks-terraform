# Plan-mode unit tests for the network module. Uses a mocked AWS provider so the
# suite runs in CI with no credentials and creates no real infrastructure.
# Guards the load-balancer subnet-tagging contract and CIDR derivation.

mock_provider "aws" {}

variables {
  cidr_block   = "10.0.0.0/16"
  project_name = "eks-test"
  tags = {
    Project     = "eks"
    Environment = "test"
  }
}

run "subnet_tagging_and_cidrs" {
  command = plan

  # Private subnets MUST be discoverable by the ALB controller for internal LBs.
  assert {
    condition     = tostring(aws_subnet.eks_subnet_private_1a.tags["kubernetes.io/role/internal-elb"]) == "1"
    error_message = "private subnet 1a must carry kubernetes.io/role/internal-elb=1"
  }
  assert {
    condition     = tostring(aws_subnet.eks_subnet_private_1b.tags["kubernetes.io/role/internal-elb"]) == "1"
    error_message = "private subnet 1b must carry kubernetes.io/role/internal-elb=1"
  }

  # Public subnets MUST NOT be tagged for public ELBs, so the controller can
  # never place an internet-facing load balancer there.
  assert {
    condition     = !contains(keys(aws_subnet.eks_subnet_public_1a.tags), "kubernetes.io/role/elb")
    error_message = "public subnet 1a must not carry kubernetes.io/role/elb"
  }
  assert {
    condition     = !contains(keys(aws_subnet.eks_subnet_public_1b.tags), "kubernetes.io/role/elb")
    error_message = "public subnet 1b must not carry kubernetes.io/role/elb"
  }

  # Subnet CIDRs derive deterministically from the VPC CIDR (within the /16
  # supernet) and are all distinct.
  assert {
    condition     = aws_subnet.eks_subnet_public_1a.cidr_block == cidrsubnet(var.cidr_block, 8, 1)
    error_message = "public subnet 1a CIDR drifted from cidrsubnet(cidr, 8, 1)"
  }
  assert {
    condition     = aws_subnet.eks_subnet_public_1b.cidr_block == cidrsubnet(var.cidr_block, 8, 2)
    error_message = "public subnet 1b CIDR drifted from cidrsubnet(cidr, 8, 2)"
  }
  assert {
    condition     = aws_subnet.eks_subnet_private_1a.cidr_block == cidrsubnet(var.cidr_block, 8, 3)
    error_message = "private subnet 1a CIDR drifted from cidrsubnet(cidr, 8, 3)"
  }
  assert {
    condition     = aws_subnet.eks_subnet_private_1b.cidr_block == cidrsubnet(var.cidr_block, 8, 4)
    error_message = "private subnet 1b CIDR drifted from cidrsubnet(cidr, 8, 4)"
  }
  assert {
    condition = length(distinct([
      aws_subnet.eks_subnet_public_1a.cidr_block,
      aws_subnet.eks_subnet_public_1b.cidr_block,
      aws_subnet.eks_subnet_private_1a.cidr_block,
      aws_subnet.eks_subnet_private_1b.cidr_block,
    ])) == 4
    error_message = "subnet CIDRs must all be distinct"
  }
}

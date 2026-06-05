# Latest Amazon Linux 2023 AMI (resolved via SSM Parameter Store).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# AWS-managed prefix list for S3 in this region. Lets us scope S3 egress to the
# gateway endpoint (CIDR-less) so the bastion reaches S3 — aws CLI, ECR layers,
# AL2023 dnf repos, and the Amazon-EKS kubectl bucket — without any internet.
data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

# Security group with no ingress: access is exclusively through SSM Session
# Manager. Egress is least-privilege (no 0.0.0.0/0). SSM works because the
# ssm/ssmmessages/ec2messages interface endpoints resolve to private VPC IPs, so
# the agent only needs in-VPC HTTPS; the private EKS API is reached the same way.
# S3 (via the gateway endpoint) covers tooling and package needs.
resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "Bastion SG - SSM-only, least-privilege egress"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to in-VPC endpoints (SSM, private EKS API, PrivateLink)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS (UDP) to the VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS (TCP) to the VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "HTTPS to S3 via the gateway endpoint (aws CLI, ECR, dnf, kubectl)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.s3.id]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-bastion-sg"
    }
  )
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  iam_instance_profile   = aws_iam_instance_profile.bastion_profile.name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  # No public IP: the bastion lives in a private subnet.
  associate_public_ip_address = false

  metadata_options {
    http_tokens   = "required" # IMDSv2 required
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  # kubectl is pulled from the Amazon-EKS S3 bucket through the S3 gateway
  # endpoint using the aws CLI (no curl, no internet egress). The build date is
  # discovered from the bucket so it never needs to be hardcoded. helm is
  # intentionally NOT installed here: Helm releases run in the workload/CI layer
  # (see ARCHITECTURE.md §7). The kubectl step is best-effort — a failure must
  # not break boot.
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    KVER="${var.kubectl_version}"
    if KDATE=$(aws s3 ls "s3://amazon-eks/$KVER/" | awk '{print $2}' | tr -d / | sort | tail -1) && [ -n "$KDATE" ]; then
      aws s3 cp "s3://amazon-eks/$KVER/$KDATE/bin/linux/amd64/kubectl" /usr/local/bin/kubectl
      chmod 0755 /usr/local/bin/kubectl
    fi

    # kubeconfig for the private cluster
    aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name} --kubeconfig /root/.kube/config || true
  EOF

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-bastion"
    }
  )
}

# Latest Amazon Linux 2023 AMI (resolved via SSM Parameter Store).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Security group with no ingress rules: access is exclusively through
# SSM Session Manager (SSM agent egress on 443 via the NAT).
resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "Bastion SG - egress only, access via SSM"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound (SSM, EKS API, image pulls via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # kubectl
    curl -sLO "https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl"
    install -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl

    # helm
    curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

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

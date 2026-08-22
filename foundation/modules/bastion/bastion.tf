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
  # Failures here are logged loudly, never swallowed. The previous version wrapped
  # the download in a bare `if` that discarded the error, so a missing IAM
  # permission looked identical to success — kubectl was simply absent, with
  # nothing in the log saying why. Boot still continues on failure (a bastion
  # without kubectl is degraded, not useless), but it says so.
  user_data = <<-EOF
    #!/bin/bash
    set -uo pipefail

    KVER="${var.kubectl_version}"
    KURL="s3://amazon-eks/$KVER"

    echo "[kubectl] resolving latest build under $KURL/"
    if ! KDATE=$(aws s3 ls "$KURL/" 2>&1 | awk '{print $2}' | tr -d / | sort | tail -1); then
      echo "[kubectl] FAILED to list $KURL/ — check the bastion role has s3:ListBucket on arn:aws:s3:::amazon-eks" >&2
    elif [ -z "$KDATE" ]; then
      echo "[kubectl] FAILED: no builds found under $KURL/ — is kubectl_version ($KVER) a full x.y.z version?" >&2
    elif ! aws s3 cp "$KURL/$KDATE/bin/linux/amd64/kubectl" /usr/local/bin/kubectl; then
      echo "[kubectl] FAILED to download — check s3:GetObject on arn:aws:s3:::amazon-eks/*" >&2
    else
      chmod 0755 /usr/local/bin/kubectl
      echo "[kubectl] installed $KVER build $KDATE at /usr/local/bin/kubectl"
      /usr/local/bin/kubectl version --client || true
    fi

    # kubeconfig for root; interactive SSM sessions run as ssm-user and should run
    # `aws eks update-kubeconfig` themselves, since each user has their own HOME.
    if aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name} --kubeconfig /root/.kube/config; then
      echo "[kubeconfig] written to /root/.kube/config"
    else
      echo "[kubeconfig] FAILED — check eks:DescribeCluster on the bastion role" >&2
    fi
  EOF

  # Changing the boot script must replace the instance: user_data only runs on
  # first boot, so without this a fixed script would sit in the config while the
  # running bastion kept the old, broken one.
  user_data_replace_on_change = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-bastion"
    }
  )
}

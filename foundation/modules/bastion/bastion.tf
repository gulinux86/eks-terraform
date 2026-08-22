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

  # kubectl comes from the in-region tooling bucket through the S3 gateway
  # endpoint — no internet egress, and no cross-region request that the gateway
  # endpoint cannot route (see tooling.tf for why that mattered).
  #
  # Boot may run before the pipeline has seeded the bucket, so the install is also
  # written out as /usr/local/bin/install-kubectl and can be re-run at any time.
  # Every failure path says what to check; the previous version swallowed errors,
  # which is why a broken download looked exactly like a working one.
  #
  # helm is intentionally NOT installed: Helm releases run in the workload layer,
  # not by hand on a host (ARCHITECTURE.md §7).
  user_data = <<-EOF
    #!/bin/bash
    set -uo pipefail

    cat > /usr/local/bin/install-kubectl <<'SCRIPT'
    #!/bin/bash
    # Installs kubectl from the project's in-region tooling bucket.
    set -uo pipefail
    SRC="s3://__BUCKET__/kubectl/__KVER__/kubectl"
    echo "[kubectl] fetching $SRC"
    if aws s3 cp "$SRC" /usr/local/bin/kubectl; then
      chmod 0755 /usr/local/bin/kubectl
      echo "[kubectl] installed at /usr/local/bin/kubectl"
      /usr/local/bin/kubectl version --client
    else
      echo "[kubectl] FAILED. Checks, in order:" >&2
      echo "  1. is the object seeded?  aws s3 ls $SRC" >&2
      echo "  2. does the bastion role allow s3:GetObject on that bucket?" >&2
      echo "  3. is the S3 gateway endpoint on this subnet's route table?" >&2
      exit 1
    fi
    SCRIPT

    sed -i "s|__BUCKET__|${aws_s3_bucket.tooling.id}|; s|__KVER__|${var.kubectl_version}|" /usr/local/bin/install-kubectl
    chmod 0755 /usr/local/bin/install-kubectl

    # Best effort at boot. If the bucket is not seeded yet, this logs why and an
    # operator can run install-kubectl later — boot is not blocked either way.
    /usr/local/bin/install-kubectl || echo "[kubectl] not installed at boot; run 'sudo install-kubectl' once the bucket is seeded" >&2

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

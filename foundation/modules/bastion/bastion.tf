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

  # Everything the operator needs is set up at boot; a session should need nothing
  # but `kubectl` (or `k`).
  #
  # The install has to survive an ordering it cannot control: the bastion is created
  # during the foundation apply, while the tooling bucket is seeded by the pipeline
  # *after* that apply finishes. So rather than try once and leave the operator to
  # fix it, a systemd unit retries until the object appears and then stops. The
  # machine converges on its own.
  #
  # helm is intentionally absent: Helm releases run in the workload layer, not by
  # hand on a host (ARCHITECTURE.md §7).
  user_data = <<-EOF
    #!/bin/bash
    set -uo pipefail

    BUCKET="${aws_s3_bucket.tooling.id}"
    KVER="${var.kubectl_version}"
    REGION="${var.region}"
    CLUSTER="${var.cluster_name}"

    # ---- installer: kubectl + a kubeconfig every user can read ----------------
    cat > /usr/local/bin/setup-kube <<SCRIPT
    #!/bin/bash
    set -uo pipefail
    SRC="s3://$BUCKET/kubectl/$KVER/kubectl"

    if [ ! -x /usr/local/bin/kubectl ]; then
      echo "[kube] fetching \$SRC"
      aws s3 cp "\$SRC" /usr/local/bin/kubectl || {
        echo "[kube] kubectl not available yet at \$SRC" >&2
        exit 1
      }
      chmod 0755 /usr/local/bin/kubectl
      echo "[kube] kubectl installed"
    fi

    # World-readable on purpose: it holds no secret. Auth is an exec call to
    # \`aws eks get-token\`, which uses the instance role — so this grants nothing
    # a user on this host did not already have.
    if [ ! -s /etc/kubeconfig ]; then
      aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" --kubeconfig /etc/kubeconfig || {
        echo "[kube] update-kubeconfig failed; check eks:DescribeCluster" >&2
        exit 1
      }
      chmod 0644 /etc/kubeconfig
      echo "[kube] kubeconfig written to /etc/kubeconfig"
    fi
    SCRIPT
    chmod 0755 /usr/local/bin/setup-kube

    # ---- retry until the bucket is seeded -------------------------------------
    cat > /etc/systemd/system/setup-kube.service <<'UNIT'
    [Unit]
    Description=Install kubectl and a shared kubeconfig
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/setup-kube
    Restart=on-failure
    RestartSec=20

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now setup-kube.service || true

    # ---- shell environment for every user -------------------------------------
    # SSM sessions run as ssm-user, not root, so a kubeconfig under /root would be
    # invisible. Pointing KUBECONFIG at the shared file is what lets a session run
    # kubectl with no setup at all.
    cat > /etc/profile.d/kube.sh <<'PROFILE'
    export KUBECONFIG=/etc/kubeconfig
    alias k=kubectl
    if command -v kubectl >/dev/null 2>&1; then
      source <(kubectl completion bash) 2>/dev/null || true
      complete -o default -F __start_kubectl k 2>/dev/null || true
    fi
    PROFILE
    chmod 0644 /etc/profile.d/kube.sh
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

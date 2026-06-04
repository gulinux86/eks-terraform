# Security group for the interface endpoints: accepts HTTPS only from within the VPC.
resource "aws_security_group" "endpoints_sg" {
  name        = "${var.project_name}-vpce-sg"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vpce-sg"
    }
  )
}

# Gateway endpoint for S3 (ECR image layers live in S3).
# No hourly cost and route-based — it does not use an ENI.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vpce-s3"
    }
  )
}

# Interface endpoints (PrivateLink) for the remaining AWS services.
# With private_dns_enabled, calls to the public AWS endpoints resolve
# to private IPs inside the VPC.
resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints_sg.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vpce-${each.value}"
    }
  )
}

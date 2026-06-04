output "subnet_pub_1a" {
  value = aws_subnet.eks_subnet_public_1a.id
}

output "subnet_pub_1b" {
  value = aws_subnet.eks_subnet_public_1b.id
}

output "subnet_private_1a" {
  value = aws_subnet.eks_subnet_private_1a.id
}

output "subnet_private_1b" {
  value = aws_subnet.eks_subnet_private_1b.id
}

output "vpc_id" {
  value = aws_vpc.eks_vpc.id
}

output "vpc_cidr" {
  value = aws_vpc.eks_vpc.cidr_block
}

output "private_subnet_ids" {
  value = [
    aws_subnet.eks_subnet_private_1a.id,
    aws_subnet.eks_subnet_private_1b.id
  ]
}

output "private_route_table_ids" {
  value = [
    aws_route_table.eks_private_route_table_1a.id,
    aws_route_table.eks_private_route_table_1b.id
  ]
}
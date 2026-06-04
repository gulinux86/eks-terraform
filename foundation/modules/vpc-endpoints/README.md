# vpc-endpoints module — S3 gateway + interface (PrivateLink) endpoints



## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_security_group.endpoints_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | Private route tables to associate with the S3 gateway endpoint | `list(string)` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Private subnets where interface endpoints ENIs are placed | `list(string)` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name to be used to name the resources (Name tag) | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region (used to build the endpoint service names) | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to be added to AWS resources | `map(any)` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR allowed to reach the interface endpoints on 443 | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the endpoints will be created | `string` | n/a | yes |
| <a name="input_interface_services"></a> [interface\_services](#input\_interface\_services) | AWS service short names for interface (PrivateLink) endpoints | `list(string)` | <pre>[<br/>  "ecr.api",<br/>  "ecr.dkr",<br/>  "sts",<br/>  "ec2",<br/>  "eks",<br/>  "kms",<br/>  "elasticloadbalancing",<br/>  "autoscaling",<br/>  "logs",<br/>  "ssm",<br/>  "ssmmessages",<br/>  "ec2messages"<br/>]</pre> | no |

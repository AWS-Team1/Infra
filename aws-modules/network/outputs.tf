output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "igw_id" {
  value = aws_internet_gateway.main.id
}

output "s3_gateway_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "public_subnet_ids" {
  value = [
    aws_subnet.public_a.id,
    aws_subnet.public_c.id
  ]
}

output "private_subnet_ids" {
  value = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id
  ]
}

output "db_subnet_ids" {
  value = [
    aws_subnet.db_a.id,
    aws_subnet.db_c.id
  ]
}

output "cache_subnet_ids" {
  value = [
    aws_subnet.cache_a.id,
    aws_subnet.cache_c.id
  ]
}

output "private_subnet_cidrs" {
  value = [
    aws_subnet.private_a.cidr_block,
    aws_subnet.private_c.cidr_block
  ]
}

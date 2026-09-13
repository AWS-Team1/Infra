output "vpc_id" {
  value = data.aws_vpc.main.id
}

output "vpc_cidr" {
  value = data.aws_vpc.main.cidr_block
}

output "igw_id" {
  value = aws_internet_gateway.main.id
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

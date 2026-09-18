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

# aws-cache 가 ElastiCache 서브넷 그룹을 만드는 데 쓴다.
output "cache_subnet_ids" {
  value = [
    aws_subnet.cache_a.id,
    aws_subnet.cache_c.id
  ]
}

# rds / elasticache 가 SG 인바운드를 CIDR 로 여는 데 쓴다.
output "private_subnet_cidrs" {
  value = [
    aws_subnet.private_a.cidr_block,
    aws_subnet.private_c.cidr_block
  ]
}

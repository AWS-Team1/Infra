# 다른 루트가 terraform_remote_state 로 읽는 계약이다.
# 이름을 바꾸면 소비 루트가 깨진다.

output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "igw_id" {
  value = module.network.igw_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "private_subnet_cidrs" {
  value = module.network.private_subnet_cidrs
}

output "db_subnet_ids" {
  value = module.network.db_subnet_ids
}

# aws-cache 가 읽는다. 프라이빗과 분리해 파드와 캐시가 NACL 경계를 공유하지 않게 한다.
output "cache_subnet_ids" {
  value = module.network.cache_subnet_ids
}

output "private_zone_id" {
  value = aws_route53_zone.test_internal.zone_id
}

output "private_zone_name" {
  value = aws_route53_zone.test_internal.name
}

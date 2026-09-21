output "cache_endpoint" {
  value = module.elasticache.cache_endpoint
}

output "cache_endpoint_address" {
  value = module.elasticache.cache_endpoint_address
}

output "secret_arn" {
  value = module.elasticache.secret_arn
}

output "user_group_id" {
  value = module.elasticache.user_group_id
}

output "cache_security_group_id" {
  value = module.elasticache.cache_security_group_id
}

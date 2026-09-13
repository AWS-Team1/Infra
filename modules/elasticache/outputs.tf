# 생성된 Serverless Cache 이름
output "cache_name" {
  value = aws_elasticache_serverless_cache.main.name
}


# WAS에서 접속할 Valkey Endpoint
output "cache_endpoint" {
  value = aws_elasticache_serverless_cache.main.endpoint
}


# ElastiCache RBAC User Group ID
output "user_group_id" {
  value = aws_elasticache_user_group.main.user_group_id
}


# Username / Password가 저장된 Secrets Manager ARN
output "secret_arn" {
  value = aws_secretsmanager_secret.valkey.arn
}

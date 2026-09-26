output "cache_endpoint" {
  value = module.elasticache.cache_endpoint
}

output "secret_arn" {
  description = "Terraform-managed Valkey credentials Secret ARN"
  value       = aws_secretsmanager_secret.valkey_credentials.arn
}

output "runtime_secret_arn" {
  description = "Terraform-managed Valkey runtime endpoint Secret ARN"
  value       = aws_secretsmanager_secret.valkey_runtime.arn
}

output "user_group_id" {
  value = module.elasticache.user_group_id
}

output "cache_security_group_id" {
  value = module.elasticache.cache_security_group_id
}

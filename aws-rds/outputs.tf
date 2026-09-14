output "db_address" {
  value = module.rds.db_address
}

output "db_port" {
  value = module.rds.db_port
}

output "db_name" {
  value = module.rds.db_name
}

output "master_user_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "db_security_group_id" {
  value = module.rds.db_security_group_id
}

# aws-dms 가 FreeStorageSpace 알람 디멘션에 쓴다.
output "db_instance_identifier" {
  value = module.rds.db_instance_identifier
}

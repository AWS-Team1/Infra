output "replication_instance_id" {
  value = module.dms.replication_instance_id
}

# Cloud SQL 쪽 방화벽이나 GCP 감사에서 출발지를 확인할 때 쓴다.
output "replication_instance_private_ips" {
  value = module.dms.replication_instance_private_ips
}

output "replication_task_ids" {
  value = module.dms.replication_task_ids
}

output "security_group_id" {
  value = module.dms.security_group_id
}

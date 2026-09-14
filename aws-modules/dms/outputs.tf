output "replication_instance_arn" {
  value = aws_dms_replication_instance.main.replication_instance_arn
}

output "replication_instance_id" {
  value = aws_dms_replication_instance.main.replication_instance_id
}

output "replication_instance_private_ips" {
  description = "Cloud SQL 쪽 방화벽에 넣을 출발지 IP"
  value       = aws_dms_replication_instance.main.replication_instance_private_ips
}

output "security_group_id" {
  value = aws_security_group.dms.id
}

output "source_endpoint_arns" {
  value = { for k, v in aws_dms_endpoint.source : k => v.endpoint_arn }
}

output "target_endpoint_arns" {
  value = { for k, v in aws_dms_endpoint.target : k => v.endpoint_arn }
}

# 런북에서 aws dms describe-replication-tasks 로 상태를 볼 때 쓴다.
output "replication_task_ids" {
  value = { for k, v in aws_dms_replication_task.main : k => v.replication_task_id }
}

output "replication_task_arns" {
  value = { for k, v in aws_dms_replication_task.main : k => v.replication_task_arn }
}

# ---------------------------------------------------------
# gitops 매니페스트에 넣어야 하는 값
# ---------------------------------------------------------
# 이 넷은 클러스터 쪽 설정과 짝이다. terraform apply 후 값이 바뀌면
# gitops 의 수집기 설정도 같이 고쳐야 한다.

output "application_log_group_name" {
  description = "수집기 awscloudwatchlogs exporter 의 log_group_name"
  value       = module.observability.application_log_group_name
}

output "emf_log_group_name" {
  description = "수집기 awsemf exporter 의 log_group_name"
  value       = module.observability.emf_log_group_name
}

output "telemetry_bucket_name" {
  description = "수집기 awss3 exporter 의 s3_bucket"
  value       = module.observability.telemetry_bucket_name
}

output "grafana_target_group_arn" {
  description = "gitops 의 TargetGroupBinding spec.targetGroupARN"
  value       = module.observability.grafana_target_group_arn
}


# ---------------------------------------------------------
# 확인용
# ---------------------------------------------------------

output "grafana_url" {
  value = "https://${aws_route53_record.grafana.fqdn}"
}

output "collector_role_arn" {
  value = module.observability.collector_role_arn
}

output "grafana_role_arn" {
  value = module.observability.grafana_role_arn
}

output "eso_role_arn" {
  value = module.observability.eso_role_arn
}

output "data_protection_audit_log_group_name" {
  description = "마스킹 감지 기록. 여기에 이벤트가 쌓이면 실제로 걸리고 있다는 뜻이다"
  value       = module.observability.data_protection_audit_log_group_name
}


# ---------------------------------------------------------
# 감사
# ---------------------------------------------------------

# 부착 대상이 0개인 것이 정상이다. 확인 명령이 아래 unmask_policy_check_command 에 있다.
output "logs_unmask_policy_arn" {
  description = "감사 시에만 사람이 부착한다. 평상시 부착 대상은 없어야 한다"
  value       = module.observability.logs_unmask_policy_arn
}


# ---------------------------------------------------------
# apply 직후 사람이 해야 하는 일
# ---------------------------------------------------------

# 와탭·Grafana 시크릿은 콘솔에서 이미 만들어 채워둔 것을 그대로 쓰므로
# Terraform 쪽에서 채우는 명령을 낼 필요가 없다 — main.tf의 SECRETS MANAGER
# 섹션 주석 참조. 남는 확인 사항은 unmask 정책 부착 여부뿐이다.
output "unmask_policy_check_command" {
  description = "unmask 정책이 아무 역할에도 붙어 있지 않은지 확인. 출력이 비어야 정상"

  value = <<-EOT
    aws iam list-entities-for-policy \
      --policy-arn ${module.observability.logs_unmask_policy_arn} \
      --query '{roles:PolicyRoles,users:PolicyUsers,groups:PolicyGroups}'
  EOT
}

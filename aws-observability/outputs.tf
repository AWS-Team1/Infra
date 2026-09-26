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

output "data_protection_audit_log_group_name" {
  description = "마스킹 감지 기록. 여기에 이벤트가 쌓이면 실제로 걸리고 있다는 뜻이다"
  value       = module.observability.data_protection_audit_log_group_name
}


# ---------------------------------------------------------
# 감사
# ---------------------------------------------------------

# 부착 대상이 0개인 것이 정상이다. 확인 명령이 아래 secret_fill_commands 에 있다.
output "logs_unmask_policy_arn" {
  description = "감사 시에만 사람이 부착한다. 평상시 부착 대상은 없어야 한다"
  value       = module.observability.logs_unmask_policy_arn
}


# ---------------------------------------------------------
# apply 직후 사람이 해야 하는 일
# ---------------------------------------------------------

# Terraform 이 시크릿 값을 넣지 않으므로, 넣는 명령을 출력으로 준다.
# 여기 실제 키가 들어가지 않는다 — 명령 문자열만 만든다.
output "secret_fill_commands" {
  description = "apply 후 실행해야 하는 명령. 와탭 키 두 개와 Grafana 비밀번호를 채운다"

  value = <<-EOT
    # 1) 와탭 프로젝트 액세스 키 — 제품별로 다르다
    #    쿠버네티스 제품 / 애플리케이션 제품 두 개를 각각 발급받아 넣는다
    #    host/port 는 와탭 콘솔의 설치 안내에 표시된 수집 서버 값을 그대로 넣는다
    #    (주석을 \ 뒤에 두면 줄 이음이 끊겨 명령이 두 개로 쪼개진다 — 여기 둔다)
    aws secretsmanager put-secret-value \
      --secret-id /${module.environment.project_name}/observability/whatap \
      --secret-string '{"kubernetes_license":"<K8S_KEY>","application_license":"<APM_KEY>","host":"<WHATAP_HOST>","port":"<WHATAP_PORT>"}'

    # 2) Grafana 관리자 비밀번호
    aws secretsmanager put-secret-value \
      --secret-id /${module.environment.project_name}/observability/grafana \
      --secret-string "{\"admin_user\":\"admin\",\"admin_password\":\"$(openssl rand -base64 24)\"}"

    # 3) unmask 정책이 아무 역할에도 붙어 있지 않은지 확인 — 출력이 비어야 정상
    aws iam list-entities-for-policy \
      --policy-arn ${module.observability.logs_unmask_policy_arn} \
      --query '{roles:PolicyRoles,users:PolicyUsers,groups:PolicyGroups}'
  EOT
}

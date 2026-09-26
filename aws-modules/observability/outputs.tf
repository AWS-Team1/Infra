# ---------------------------------------------------------
# 로그 그룹
# ---------------------------------------------------------
# 아래 세 이름은 gitops 의 수집기 설정(awscloudwatchlogs · awsemf exporter)에
# 그대로 들어간다. 이름이 어긋나면 수집기가 AccessDenied 로 실패한다.

output "application_log_group_name" {
  value = aws_cloudwatch_log_group.application.name
}

output "emf_log_group_name" {
  value = aws_cloudwatch_log_group.emf.name
}

output "data_protection_audit_log_group_name" {
  value = aws_cloudwatch_log_group.data_protection_audit.name
}


# ---------------------------------------------------------
# 텔레메트리 장기 보관
# ---------------------------------------------------------

output "telemetry_bucket_name" {
  description = "수집기의 awss3 exporter 에 넣는 버킷 이름. 비활성화하면 빈 문자열"
  value       = var.enable_telemetry_archive ? aws_s3_bucket.telemetry[0].bucket : ""
}

output "telemetry_bucket_arn" {
  value = var.enable_telemetry_archive ? aws_s3_bucket.telemetry[0].arn : ""
}


# ---------------------------------------------------------
# IAM
# ---------------------------------------------------------

output "collector_role_arn" {
  value      = aws_iam_role.collector.arn
  depends_on = [aws_iam_role_policy_attachment.collector]
}

output "grafana_role_arn" {
  value      = aws_iam_role.grafana.arn
  depends_on = [aws_iam_role_policy_attachment.grafana]
}

output "eso_role_arn" {
  value      = aws_iam_role.eso.arn
  depends_on = [aws_iam_role_policy_attachment.eso]
}

# 감사용. 어떤 역할에도 붙어 있지 않은 것이 정상 상태다.
output "logs_unmask_policy_arn" {
  description = "감사 시 사람이 의도적으로 부착하는 정책. 평상시 부착 대상은 없어야 한다"
  value       = aws_iam_policy.logs_unmask.arn
}


# ---------------------------------------------------------
# Grafana 노출
# ---------------------------------------------------------

# gitops 의 TargetGroupBinding spec.targetGroupARN 에 넣는다.
output "grafana_target_group_arn" {
  value = aws_lb_target_group.grafana.arn
}

output "grafana_host" {
  value = var.grafana_host
}

output "dashboard_name" {
  description = "CloudWatch dashboard 이름"
  value       = aws_cloudwatch_dashboard.infrastructure.dashboard_name
}

output "dashboard_url" {
  description = "AWS 콘솔에서 dashboard를 여는 URL"
  value       = "https://${module.environment.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${module.environment.aws_region}#dashboards/dashboard/${urlencode(aws_cloudwatch_dashboard.infrastructure.dashboard_name)}"
}

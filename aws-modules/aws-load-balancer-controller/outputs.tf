output "iam_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.this.arn
}

output "service_account_name" {
  description = "ServiceAccount name"
  value       = kubernetes_service_account_v1.this.metadata[0].name
}

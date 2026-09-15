output "application_database_secret_name" {
  value = aws_secretsmanager_secret.app_database.name
}

output "db_bootstrap_role_arn" {
  value = aws_iam_role.db_bootstrap.arn
}

output "db_bootstrap_pod_identity_association_id" {
  value = aws_eks_pod_identity_association.db_bootstrap.association_id
}

output "database_private_dns_name" {
  value = aws_route53_record.database.fqdn
}

output "argocd_url" {
  value = "https://${aws_route53_record.argocd.fqdn}"
}

output "argocd_target_group_arn" {
  value = data.terraform_remote_state.ops.outputs.argocd_target_group_arn
}

output "ops_alb_security_group_id" {
  value = data.terraform_remote_state.ops.outputs.ops_alb_security_group_id
}

output "rds_master_secret_arn" {
  value = data.terraform_remote_state.rds.outputs.master_user_secret_arn
}

# GitOps 준비 스크립트가 값을 주입할 기존 호환용 DB Secret 이름이다.
output "application_database_secret_name" {
  value = data.aws_secretsmanager_secret.app_database.name
}

# 운영 확인이나 외부 자동화에서 bootstrap 전용 역할을 식별할 ARN이다.
output "db_bootstrap_role_arn" {
  value = aws_iam_role.db_bootstrap.arn
}

# ServiceAccount와 IAM 역할의 연결이 생성됐는지 확인할 Association ID다.
output "db_bootstrap_pod_identity_association_id" {
  value = aws_eks_pod_identity_association.db_bootstrap.association_id
}

# bootstrap SecretProviderClass가 참조할 RDS master Secret의 정확한 ARN이다.
output "rds_master_secret_arn" {
  value = data.terraform_remote_state.rds.outputs.master_user_secret_arn
}

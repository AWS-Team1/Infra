output "jwt_public_secret_arn" { value = aws_secretsmanager_secret.jwt_public.arn }
output "jwt_private_secret_arn" { value = aws_secretsmanager_secret.jwt_private.arn }
output "app_database_secret_arn" { value = aws_secretsmanager_secret.app_database.arn }
output "accounts_database_secret_arn" { value = aws_secretsmanager_secret.accounts_database.arn }
output "ledger_database_secret_arn" { value = aws_secretsmanager_secret.ledger_database.arn }
output "app_database_secret_name" { value = aws_secretsmanager_secret.app_database.name }

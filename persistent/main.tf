# Secret containers and application credentials survive routine EKS/RDS teardown.
# The explicit full-teardown path can still destroy this root.
resource "aws_secretsmanager_secret" "jwt_public" {
  name                    = "/${module.environment.project_name}/jwt/public"
  recovery_window_in_days = 0

  tags = { Name = "${module.environment.project_name}-jwt-public" }
}

resource "aws_secretsmanager_secret" "jwt_private" {
  name                    = "/${module.environment.project_name}/jwt/private"
  recovery_window_in_days = 0

  tags = { Name = "${module.environment.project_name}-jwt-private" }
}

resource "aws_secretsmanager_secret" "app_database" {
  name                    = "/${module.environment.project_name}/database/app"
  description             = "Bank of Anthos least-privilege application database credential"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "accounts_database" {
  name                    = "/${module.environment.project_name}/database/accounts"
  description             = "Bank of Anthos accounts service least-privilege database credential"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "ledger_database" {
  name                    = "/${module.environment.project_name}/database/ledger"
  description             = "Bank of Anthos ledger service least-privilege database credential"
  recovery_window_in_days = 7
}

ephemeral "random_password" "app_database" {
  length  = 64
  special = false
}

ephemeral "random_password" "accounts_database" {
  length  = 64
  special = false
}

ephemeral "random_password" "ledger_database" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "app_database" {
  secret_id                = aws_secretsmanager_secret.app_database.id
  secret_string_wo         = jsonencode({ username = "bank_app", password = ephemeral.random_password.app_database.result })
  secret_string_wo_version = 2298761427
}

resource "aws_secretsmanager_secret_version" "accounts_database" {
  secret_id                = aws_secretsmanager_secret.accounts_database.id
  secret_string_wo         = jsonencode({ username = "accounts_app", password = ephemeral.random_password.accounts_database.result })
  secret_string_wo_version = 1017649738
}

resource "aws_secretsmanager_secret_version" "ledger_database" {
  secret_id                = aws_secretsmanager_secret.ledger_database.id
  secret_string_wo         = jsonencode({ username = "ledger_app", password = ephemeral.random_password.ledger_database.result })
  secret_string_wo_version = 47741656
}

# This root owns only the EKS/RDS-dependent binding layer. Long-lived Secret
# containers and application credential versions are owned by persistent.
data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = module.environment.state_bucket
    key    = "aws/eks/terraform.tfstate"
    region = module.environment.aws_region
  }
}

data "terraform_remote_state" "rds" {
  backend = "s3"

  config = {
    bucket = module.environment.state_bucket
    key    = "aws/rds/terraform.tfstate"
    region = module.environment.aws_region
  }
}

data "aws_secretsmanager_secret" "app_database" {
  name = "/${module.environment.project_name}/database/app"
}

data "aws_secretsmanager_secret" "accounts_database" {
  name = "/${module.environment.project_name}/database/accounts"
}

data "aws_secretsmanager_secret" "ledger_database" {
  name = "/${module.environment.project_name}/database/ledger"
}

resource "aws_iam_role" "db_bootstrap" {
  name        = "${module.environment.project_name}-db-bootstrap-sm"
  description = "EKS Pod Identity role for Bank of Anthos database bootstrap"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "db_bootstrap_secrets" {
  name = "BoaDatabaseBootstrapSecrets"
  role = aws_iam_role.db_bootstrap.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadBootstrapSecrets"
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [
        data.terraform_remote_state.rds.outputs.master_user_secret_arn,
        data.aws_secretsmanager_secret.app_database.arn,
        data.aws_secretsmanager_secret.accounts_database.arn,
        data.aws_secretsmanager_secret.ledger_database.arn
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "db_bootstrap" {
  cluster_name    = data.terraform_remote_state.eks.outputs.cluster_name
  namespace       = "bank-of-anthos"
  service_account = "bank-of-anthos-db-bootstrap"
  role_arn        = aws_iam_role.db_bootstrap.arn
}

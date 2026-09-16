data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# 기존 독립 root의 output을 계약으로 사용한다. 적용 순서는 README/runbook을 따른다.
data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    # HARD-CODED: 다른 환경의 backend 위치에 맞게 변경한다.
    bucket = "boa-terraform-state-6416"
    key    = "aws/eks/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "rds" {
  backend = "s3"

  config = {
    # HARD-CODED: 다른 환경의 backend 위치에 맞게 변경한다.
    bucket = "boa-terraform-state-6416"
    key    = "aws/rds/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "ops" {
  backend = "s3"

  config = {
    # HARD-CODED: 다른 환경의 backend 위치에 맞게 변경한다.
    bucket = "boa-terraform-state-6416"
    key    = "aws/ops/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

check "account_guard" {
  assert {
    # HARD-CODED: 반드시 실제 배포 대상 AWS Account ID로 변경한다.
    condition     = data.aws_caller_identity.current.account_id == "769413326616"
    error_message = "Wrong AWS account. Expected 769413326616."
  }
}

# 값은 Terraform에 넣지 않는다. GitOps prepare-database-secret.sh가 최초 한 번
# stdin으로 값을 주입하므로 비밀번호가 코드/plan/명령 인자에 남지 않는다.
resource "aws_secretsmanager_secret" "app_database" {
  # HARD-CODED: 애플리케이션 SecretProviderClass와 같은 이름이어야 한다.
  name                    = "/boa/database/app"
  description             = "Bank of Anthos least-privilege application database credential"
  recovery_window_in_days = 0

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret" "accounts_database" {
  name                    = "/boa/database/accounts"
  description             = "Bank of Anthos accounts service least-privilege database credential"
  recovery_window_in_days = 7

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret" "ledger_database" {
  name                    = "/boa/database/ledger"
  description             = "Bank of Anthos ledger service least-privilege database credential"
  recovery_window_in_days = 7

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "db_bootstrap" {
  # HARD-CODED: GitOps 문서와 운영 명명 규칙에 맞춰 변경할 수 있다.
  name        = "boa-db-bootstrap-sm"
  description = "EKS Pod Identity role for Bank of Anthos database bootstrap"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
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
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = [
        data.terraform_remote_state.rds.outputs.master_user_secret_arn,
        aws_secretsmanager_secret.app_database.arn,
        aws_secretsmanager_secret.accounts_database.arn,
        aws_secretsmanager_secret.ledger_database.arn
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "db_bootstrap" {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name

  # HARD-CODED: GitOps의 namespace/ServiceAccount와 반드시 동일해야 한다.
  namespace       = "bank-of-anthos"
  service_account = "bank-of-anthos-db-bootstrap"
  role_arn        = aws_iam_role.db_bootstrap.arn
}

data "aws_route53_zone" "private" {
  # HARD-CODED: 애플리케이션 DB_HOST와 같은 Private Hosted Zone이다.
  name         = "boa.internal."
  private_zone = true
}

resource "aws_route53_record" "database" {
  zone_id = data.aws_route53_zone.private.zone_id
  # HARD-CODED: GitOps의 db.boa.internal 참조와 같아야 한다.
  name    = "db.boa.internal"
  type    = "CNAME"
  ttl     = 60
  records = [data.terraform_remote_state.rds.outputs.db_address]
}

data "aws_route53_zone" "public" {
  # HARD-CODED: ACM 인증서와 ops ALB Host 조건에 맞는 Public Hosted Zone이다.
  name         = "bespinglobal.site."
  private_zone = false
}

resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.public.zone_id
  # HARD-CODED: aws-ops의 argocd_host와 반드시 같아야 한다.
  name    = "argocd.bespinglobal.site"
  type    = "CNAME"
  ttl     = 60
  records = [data.terraform_remote_state.ops.outputs.ops_alb_dns_name]
}

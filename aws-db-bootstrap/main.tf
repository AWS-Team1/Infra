# aws-rds ── RDS master Secret ARN ──┐
#                                     ├─ aws-db-bootstrap
# aws-eks ── EKS cluster name ───────┘
#
# 이 root는 RDS를 만들지 않는다. EKS의 DB 초기화 Job만 RDS master 자격 증명과
# 애플리케이션 DB Secret을 읽도록 연결해, 일반 애플리케이션 권한과 수명주기를 분리한다.
# 적용 순서: aws-core → aws-rds와 aws-eks → aws-db-bootstrap → GitOps db-bootstrap Job

# EKS state에서 cluster_name을 가져와 아래 Pod Identity Association의 대상을 정한다.
# Association은 실제 클러스터에 생성되는 AWS 리소스이므로 EKS가 먼저 존재해야 한다.
# 이름을 하드코딩해도 이 의존성은 사라지지 않으며, ServiceAccount 자체는 GitOps가 만든다.
data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    # HARD-CODED: 다른 환경의 backend 위치에 맞게 변경한다.
    bucket = "boa-terraform-state-6416"
    key    = "aws/eks/terraform.tfstate"
    region = "ap-northeast-2"
  }
}


# RDS state에서 AWS가 관리하는 master 사용자 Secret ARN을 가져온다.
# 이 Secret은 일반 앱이 아니라 bootstrap 전용 역할만 읽으며, Job은 그 권한으로
# 데이터베이스·역할·스키마와 서비스별 최소 권한을 최초 설정한다.
data "terraform_remote_state" "rds" {
  backend = "s3"

  config = {
    # HARD-CODED: 다른 환경의 backend 위치에 맞게 변경한다.
    bucket = "boa-terraform-state-6416"
    key    = "aws/rds/terraform.tfstate"
    region = "ap-northeast-2"
  }
}


# 아래 세 리소스는 Secret 컨테이너를 만든다.
# /boa/database/app은 기존 단일 bank_app 계정 구조와의 호환을 위해 유지한다.
resource "aws_secretsmanager_secret" "app_database" {
  # HARD-CODED: 애플리케이션 SecretProviderClass와 같은 이름이어야 한다.
  name                    = "/boa/database/app"
  description             = "Bank of Anthos least-privilege application database credential"
  recovery_window_in_days = 0

  lifecycle {
    prevent_destroy = false
  }
}

# accounts 서비스가 accountsdb에 최소 권한으로 접속할 자격 증명 컨테이너다.
resource "aws_secretsmanager_secret" "accounts_database" {
  name                    = "/boa/database/accounts"
  description             = "Bank of Anthos accounts service least-privilege database credential"
  recovery_window_in_days = 7

  lifecycle {
    prevent_destroy = true
  }
}

# ledger 서비스가 ledgerdb에 최소 권한으로 접속할 자격 증명 컨테이너다.
resource "aws_secretsmanager_secret" "ledger_database" {
  name                    = "/boa/database/ledger"
  description             = "Bank of Anthos ledger service least-privilege database credential"
  recovery_window_in_days = 7

  lifecycle {
    prevent_destroy = true
  }
}

# 평문을 파일·plan·state에 남기지 않는다. 비밀번호는 apply 중 메모리에서만
# 생성되어 write-only 인자로 Secrets Manager에 전달된다.
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
  secret_id        = aws_secretsmanager_secret.app_database.id
  secret_string_wo = jsonencode({ username = "bank_app", password = ephemeral.random_password.app_database.result })
  # 비밀값이 아닌 생성 토큰이다. 의도적으로 비밀번호를 바꿀 때만 변경한다.
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

# DB bootstrap Pod만 맡는 EKS Pod Identity용 역할이다. 신뢰 주체를
# pods.eks.amazonaws.com으로 제한해 RDS master 권한이 일반 앱 Pod에 노출되지 않게 한다.
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

# bootstrap 역할이 읽을 Secret을 master와 위 세 DB Secret의 정확한 ARN으로 제한한다.
# rds!db-* 와일드카드를 쓰지 않아 다른 RDS 인스턴스의 master Secret은 읽을 수 없다.
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

# EKS cluster → bank-of-anthos namespace → bank-of-anthos-db-bootstrap ServiceAccount
# → boa-db-bootstrap-sm IAM role을 연결한다. 실제 EKS 클러스터에 Association을 만들기
# 때문에 이 root가 aws-eks state의 cluster_name을 참조한다.
resource "aws_eks_pod_identity_association" "db_bootstrap" {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name

  # HARD-CODED: GitOps의 namespace/ServiceAccount와 반드시 동일해야 한다.
  namespace       = "bank-of-anthos"
  service_account = "bank-of-anthos-db-bootstrap"
  role_arn        = aws_iam_role.db_bootstrap.arn
}


# aws-core 가 만든 VPC·서브넷을 읽는다. aws-eks 는 참조하지 않는다.
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = module.environment.state_bucket
    key    = "aws/core/terraform.tfstate"
    region = module.environment.aws_region
  }
}

locals {
  # Increase this value to rotate the Secrets Manager and ElastiCache
  # credentials together.
  valkey_credentials_version = 1
  valkey_username            = "redis"
}

# The password exists only during the Terraform operation and is passed only
# to write-only arguments, so its plaintext is not stored in plan or state.
ephemeral "random_password" "valkey" {
  length  = 32
  special = false

  upper   = true
  lower   = true
  numeric = true

  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "aws_secretsmanager_secret" "valkey_credentials" {
  name                    = "/${module.environment.project_name}/valkey/credentials"
  recovery_window_in_days = 0

  tags = {
    Name = "${module.environment.project_name}-valkey-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "valkey_credentials" {
  secret_id = aws_secretsmanager_secret.valkey_credentials.id

  secret_string_wo = jsonencode({
    username = local.valkey_username
    password = ephemeral.random_password.valkey.result
  })
  secret_string_wo_version = local.valkey_credentials_version
}

# Migration-only ownership for the former active user. Keeping it managed
# avoids an orphaned AWS resource and lets routine aws-cache destroy remove it.
# It is deliberately excluded from the active User Group below.
resource "aws_elasticache_user" "valkey_legacy" {
  user_id       = "boa-app"
  user_name     = "boa-app"
  access_string = "on ~* +@all"
  engine        = "valkey"

  passwords_wo         = ephemeral.random_password.valkey.result
  passwords_wo_version = local.valkey_credentials_version

  tags = {
    Name = "boa-app"
  }

  depends_on = [aws_secretsmanager_secret_version.valkey_credentials]
}

# =========================================================
# ElastiCache Serverless Valkey
# - 로그인 Session / Cache 용도
# =========================================================

module "elasticache" {
  source = "../aws-modules/elasticache"

  project_name = module.environment.project_name

  # Cache name and the final runtime RBAC username.
  cache_name          = "boa-valkey"
  user_name           = local.valkey_username
  user_password       = ephemeral.random_password.valkey.result
  credentials_version = local.valkey_credentials_version

  vpc_id               = data.terraform_remote_state.core.outputs.vpc_id
  private_subnet_cidrs = data.terraform_remote_state.core.outputs.private_subnet_cidrs

  # ElastiCache 전용 서브넷. 프라이빗(EKS 파드)과 분리한다.
  # private_subnet_cidrs 는 위에서 SG 인바운드용으로 따로 받는다 —
  # 허용 대상은 클라이언트(파드)가 있는 곳이라 캐시 위치와 무관하다.
  subnet_ids = data.terraform_remote_state.core.outputs.cache_subnet_ids

  # Phase 1 테스트용 낮은 사용량 상한
  max_data_storage    = 1
  max_ecpu_per_second = 1000

  # Persist the same generated credential before updating the Valkey user.
  depends_on = [aws_secretsmanager_secret_version.valkey_credentials]
}

resource "aws_secretsmanager_secret" "valkey_runtime" {
  name                    = "/${module.environment.project_name}/valkey/runtime"
  recovery_window_in_days = 0

  tags = {
    Name = "${module.environment.project_name}-valkey-runtime"
  }
}

resource "aws_secretsmanager_secret_version" "valkey_runtime" {
  secret_id = aws_secretsmanager_secret.valkey_runtime.id

  secret_string = jsonencode({
    host = module.elasticache.cache_endpoint[0].address
  })
}

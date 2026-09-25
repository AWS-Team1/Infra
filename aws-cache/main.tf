# aws-core 가 만든 VPC·서브넷을 읽는다. aws-eks 는 참조하지 않는다.
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  # 이 값을 올리면 Secrets Manager와 ElastiCache 비밀번호가 함께 갱신된다.
  valkey_credentials_version = 1
}

# 실행 중에만 존재하는 비밀번호. write-only 인수에만 전달하여 plan/state에 남기지 않는다.
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

# Valkey 자격 증명의 영구 저장소. Secret과 수명주기는 Terraform이 관리한다.
resource "aws_secretsmanager_secret" "valkey_credentials" {
  name                    = "/boa/valkey/credentials"
  recovery_window_in_days = 0

  tags = {
    Name = "boa-valkey-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "valkey_credentials" {
  secret_id = aws_secretsmanager_secret.valkey_credentials.id

  secret_string_wo = jsonencode({
    username = "redis"
    password = ephemeral.random_password.valkey.result
  })

  secret_string_wo_version = local.valkey_credentials_version
}

# =========================================================
# ElastiCache Serverless Valkey
# - 로그인 Session / Cache 용도
# =========================================================

module "elasticache" {
  source = "../aws-modules/elasticache"

  project_name = "boa"

  # Cache 이름과 Terraform이 생성하는 RBAC 자격 증명
  cache_name          = "boa-valkey"
  user_name           = "redis"
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

  # Secret 저장이 끝난 뒤 같은 자격 증명으로 Valkey 사용자를 생성한다.
  depends_on = [
    aws_secretsmanager_secret_version.valkey_credentials
  ]
}

# 캐시가 교체되어 endpoint가 바뀌면 이 Secret Version도 함께 갱신된다.
# host는 비밀값이 아니지만 기존 CSI 전달 경로를 재사용하기 위해 Secrets Manager에 둔다.
resource "aws_secretsmanager_secret" "valkey_runtime" {
  name                    = "/boa/valkey/runtime"
  recovery_window_in_days = 0

  tags = {
    Name = "boa-valkey-runtime"
  }
}

resource "aws_secretsmanager_secret_version" "valkey_runtime" {
  secret_id = aws_secretsmanager_secret.valkey_runtime.id

  secret_string = jsonencode({
    host = module.elasticache.cache_endpoint[0].address
  })
}

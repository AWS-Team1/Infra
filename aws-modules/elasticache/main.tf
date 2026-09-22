# =========================================================
# Secrets Manager
# - 운영자가 미리 만든 Username / Password를 읽는다.
# - Secret 및 Secret Version의 생명주기는 Terraform이 관리하지 않는다.
# =========================================================

data "aws_secretsmanager_secret" "valkey" {
  name = var.credentials_secret_name
}

data "aws_secretsmanager_secret_version" "valkey" {
  secret_id     = data.aws_secretsmanager_secret.valkey.id
  version_stage = "AWSCURRENT"
}

locals {
  valkey_credentials = jsondecode(data.aws_secretsmanager_secret_version.valkey.secret_string)
}


# =========================================================
# ElastiCache RBAC User
# - WAS가 Valkey 접속 시 사용할 사용자
# - Phase 1에서는 모든 Key / Command 허용
# =========================================================

# Valkey RBAC 사용자. 위 비밀번호로 인증하며 Phase 1 은 모든 키·명령을 허용한다.
resource "aws_elasticache_user" "app" {
  user_id       = local.valkey_credentials.username
  user_name     = local.valkey_credentials.username
  access_string = "on ~* +@all"
  engine        = "valkey"

  authentication_mode {
    type      = "password"
    passwords = [local.valkey_credentials.password]
  }

  tags = {
    Name = local.valkey_credentials.username
  }

  lifecycle {
    # username(user_id)이 바뀌면 새 사용자를 먼저 만들고 User Group을
    # 전환한 다음 기존 사용자를 제거한다.
    create_before_destroy = true

    precondition {
      condition = (
        can(local.valkey_credentials.username) &&
        can(local.valkey_credentials.password) &&
        can(regex("^[A-Za-z][A-Za-z0-9-]*$", try(local.valkey_credentials.username, ""))) &&
        length(try(local.valkey_credentials.password, "")) >= 16 &&
        length(try(local.valkey_credentials.password, "")) <= 128 &&
        !can(regex("[,\"'/@]", try(local.valkey_credentials.password, "")))
      )
      error_message = "Valkey username must start with a letter and contain only letters, numbers, and hyphens. Password must be 16-128 characters and must not contain comma, quotes, slash, or @."
    }
  }
}


# =========================================================
# ElastiCache User Group
# - 위에서 생성한 project-app 사용자를
#   Valkey Serverless Cache와 연결하기 위한 그룹
# =========================================================

# 위 사용자를 캐시에 붙이기 위한 그룹. 캐시는 사용자가 아니라 그룹을 참조한다.
resource "aws_elasticache_user_group" "main" {
  engine        = "valkey"
  user_group_id = "${var.project_name}-valkey-users"

  user_ids = [
    aws_elasticache_user.app.user_id
  ]

  tags = {
    Name = "${var.project_name}-valkey-users"
  }
}


# =========================================================
# ElastiCache Serverless Valkey
# =========================================================

# Valkey Serverless 캐시. userservice 가 회원가입 시 signup:<username> 락에 쓴다.
# SG 는 같은 모듈의 security.tf 것, 서브넷은 EKS 와 같은 프라이빗 서브넷이다.
# snapshot_retention_limit = 0 — 잃어도 되는 데이터라는 전제다.
resource "aws_elasticache_serverless_cache" "main" {
  name   = var.cache_name
  engine = "valkey"

  # EKS와 동일한 Private Subnet A/C 사용
  subnet_ids = var.subnet_ids

  # ElastiCache 전용 Security Group
  security_group_ids = [
    aws_security_group.cache.id
  ]

  # RBAC 인증에 사용할 User Group
  user_group_id = aws_elasticache_user_group.main.user_group_id

  # 테스트 환경 비용 제어
  cache_usage_limits {
    data_storage {
      maximum = var.max_data_storage
      unit    = "GB"
    }

    ecpu_per_second {
      maximum = var.max_ecpu_per_second
    }
  }

  # Phase 1에서는 자동 Snapshot 사용하지 않음
  snapshot_retention_limit = 0

  tags = {
    Name = var.cache_name
  }
}

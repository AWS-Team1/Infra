# Secret 컨테이너와 {"username":"...","password":"..."} 값은 운영자가 먼저 만든다.
# ephemeral data와 write-only 인자를 사용해 비밀번호를 plan/state에 저장하지 않는다.
data "aws_secretsmanager_secret" "valkey" {
  name = var.credentials_secret_name
}

ephemeral "aws_secretsmanager_secret_version" "valkey" {
  secret_id = data.aws_secretsmanager_secret.valkey.id
}

locals {
  valkey_credentials = jsondecode(ephemeral.aws_secretsmanager_secret_version.valkey.secret_string)
}


# =========================================================
# ElastiCache RBAC User
# - WAS가 Valkey 접속 시 사용할 사용자
# - Phase 1에서는 모든 Key / Command 허용
# =========================================================

# Valkey RBAC 사용자. 위 비밀번호로 인증하며 Phase 1 은 모든 키·명령을 허용한다.
resource "aws_elasticache_user" "app" {
  user_id              = var.user_name
  user_name            = var.user_name
  access_string        = "on ~* +@all"
  engine               = "valkey"
  passwords_wo         = local.valkey_credentials.password
  passwords_wo_version = var.credentials_version

  tags = {
    Name = var.user_name
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

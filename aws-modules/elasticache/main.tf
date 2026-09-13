# =========================================================
# Valkey Password
# - Phase 1에서는 Terraform이 랜덤 비밀번호 생성
# =========================================================

resource "random_password" "valkey" {
  length  = 32
  special = false
}


# =========================================================
# Secrets Manager
# - WAS에서 사용할 Valkey Username / Password 보관
# =========================================================

resource "aws_secretsmanager_secret" "valkey" {
  name = "/${var.project_name}/valkey/credentials"

  tags = {
    Name = "${var.project_name}-valkey-credentials"
  }
}


# 실제 Username / Password 값을 Secret에 저장
resource "aws_secretsmanager_secret_version" "valkey" {
  secret_id = aws_secretsmanager_secret.valkey.id

  secret_string = jsonencode({
    username = var.user_name
    password = random_password.valkey.result
  })
}


# =========================================================
# ElastiCache RBAC User
# - WAS가 Valkey 접속 시 사용할 사용자
# - Phase 1에서는 모든 Key / Command 허용
# =========================================================

resource "aws_elasticache_user" "app" {
  user_id       = var.user_name
  user_name     = var.user_name
  access_string = "on ~* +@all"
  engine        = "valkey"

  authentication_mode {
    type      = "password"
    passwords = [random_password.valkey.result]
  }

  tags = {
    Name = var.user_name
  }
}


# =========================================================
# ElastiCache User Group
# - 위에서 생성한 project-app 사용자를
#   Valkey Serverless Cache와 연결하기 위한 그룹
# =========================================================

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

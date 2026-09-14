# =========================================================
# Valkey Password
# - Phase 1에서는 Terraform이 랜덤 비밀번호 생성
# =========================================================

# Valkey RBAC 사용자의 비밀번호. state 에 평문으로 남는다.
resource "random_password" "valkey" {
  length  = 32
  special = false
}


# =========================================================
# Secrets Manager
# - WAS에서 사용할 Valkey Username / Password 보관
# =========================================================

# 애플리케이션이 읽을 자리. eks-iam 의 bank-of-anthos 정책이 /boa/* 를 허용한다.
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

# Valkey RBAC 사용자. 위 비밀번호로 인증하며 Phase 1 은 모든 키·명령을 허용한다.
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

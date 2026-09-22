# =========================================================
# Cloud SQL for PostgreSQL — DR 대기 인스턴스
#
# 이 인스턴스는 AWS DMS 의 "대상"이다. GCP DMS 를 쓰지 않으므로
# 복제본(replica)이 아니라 처음부터 독립된 쓰기 가능 인스턴스다.
# 따라서 "승격(promote)"이라는 단계가 없다 — 앱이 여기를 바라보면 그게 전환이다.
#
# 그 대가로 읽기 전용 보호막이 없다. 대기 기간 동안 앱 계정이 실수로
# 쓰지 못하도록 아래 app_read_only 플래그를 함께 둔다(가드레일이지 잠금은 아니다).
# =========================================================

resource "google_sql_database_instance" "main" {
  name             = var.instance_name
  database_version = var.database_version
  region           = var.region

  # 대기 인스턴스를 실수로 지우는 것을 막는다. 정리할 때는 false 로 바꿔 apply 한 뒤 destroy.
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_type         = "PD_SSD"
    disk_size         = var.disk_size
    disk_autoresize   = true

    ip_configuration {
      # 퍼블릭 IP 를 주지 않는다. AWS DMS 는 VPN 을 타고 사설 IP 로 붙는다.
      ipv4_enabled    = false
      private_network = var.network_id

      # VPN 너머 AWS 대역에서 오는 접속을 허용하려면 필요하다.
      # (PSA 피어링의 export_custom_routes 와 짝이다)
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "17:00" # UTC. KST 02:00
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days
    }

    # 느린 쿼리 로깅. AWS 쪽 log_min_duration_statement=1000 과 맞춘다.
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }

    # AWS DMS 가 대상에 쓰는 동안 FK 트리거를 우회할 수 있게 한다.
    # (대상 엔드포인트의 AfterConnectScript 가 세션 단위로 replica 를 설정한다)
    database_flags {
      name  = "cloudsql.logical_decoding"
      value = "on"
    }

    maintenance_window {
      day          = 7 # 일요일
      hour         = 18
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
    }

    user_labels = {
      project   = var.project_name
      component = "cloudsql"
      role      = "dr-standby"
    }
  }

  # PSA 연결이 없으면 사설 IP 할당이 실패한다.
  # var.psa_connection 을 lifecycle 에서 참조해 순서를 문서화한다.
  # (depends_on 은 리소스 참조만 받으므로 변수를 넣을 수 없다. 루트 간 순서는
  #  apply 순서로 보장한다 — 런북 §3 참고)
  lifecycle {
    precondition {
      condition     = var.psa_connection != ""
      error_message = "gcp-core 의 psa_connection 출력이 비어 있다. gcp-core 를 먼저 apply 해야 한다."
    }
  }
}


# 애플리케이션용 논리 DB 2개.
# AWS 쪽은 GitOps 의 db-bootstrap Job 이 CREATE DATABASE 로 만들지만,
# GCP 쪽은 Terraform 이 만든다 — 클러스터가 아직 없어도 DMS 를 붙일 수 있어야 하기 때문이다.
# 스키마(테이블)는 여기서 만들지 않는다. db-bootstrap Job 의 GCP 컴포넌트가 맡는다.
resource "google_sql_database" "app" {
  for_each = toset(var.app_database_names)

  name     = each.value
  instance = google_sql_database_instance.main.name

  # 앱 스키마가 들어 있는 DB 를 Terraform 이 지우지 못하게 한다.
  deletion_policy = "ABANDON"
}


# DMS 대상 엔드포인트가 쓸 계정. 대상 DB 에 DDL·DML 권한이 필요하다.
resource "google_sql_user" "dms" {
  name                = var.dms_username
  instance            = google_sql_database_instance.main.name
  password_wo         = var.dms_password
  password_wo_version = 1
}

# accounts 서비스 전용 로그인 계정.
resource "google_sql_user" "accounts" {
  name                = var.accounts_username
  instance            = google_sql_database_instance.main.name
  password_wo         = var.accounts_password
  password_wo_version = 1
}

# ledger 서비스 전용 로그인 계정.
resource "google_sql_user" "ledger" {
  name                = var.ledger_username
  instance            = google_sql_database_instance.main.name
  password_wo         = var.ledger_password
  password_wo_version = 1
}

# GKE bootstrap Job 전용 built-in 사용자. Cloud SQL은 built-in 사용자를
# cloudsqlsuperuser 멤버로 생성하므로 이 계정만 role/grant 정리에 사용한다.
resource "google_sql_user" "bootstrap" {
  name                = var.bootstrap_username
  instance            = google_sql_database_instance.main.name
  password_wo         = var.bootstrap_password
  password_wo_version = 1
}

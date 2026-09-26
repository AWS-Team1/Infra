# DB Subnet Group
# RDS 를 어느 서브넷에 놓을지. aws-core 의 db 서브넷 2개(다른 AZ)를 받는다.
# Multi-AZ 는 서로 다른 AZ 의 서브넷 2개 이상을 요구한다.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}


# PostgreSQL Custom Parameter Group
# PostgreSQL 파라미터. 1초 넘는 쿼리를 로그로 남긴다(느린 쿼리 추적).
#
# rds.logical_replication — AWS DMS 의 CDC(변경 데이터 캡처)가 논리 복제 슬롯을
# 만들려면 반드시 1 이어야 한다. 이 값을 켜면 RDS 가 wal_level·max_wal_senders·
# max_replication_slots 를 함께 맞춰준다.
#
# 주의 두 가지
#  1. 정적 파라미터다. apply 만으로는 반영되지 않고 인스턴스 재부팅이 필요하다.
#     Multi-AZ 이므로 재부팅이 AZ 페일오버를 동반할 수 있다.
#  2. 켠 뒤에는 WAL 생성량이 늘어난다. 복제 슬롯을 쓰지 않게 되면
#     반드시 pg_drop_replication_slot() 으로 지운다. 안 지우면 소비되지 않은
#     WAL 이 계속 쌓여 인스턴스 스토리지를 채운다.
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-postgres16"
  family = "postgres16"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name         = "rds.logical_replication"
    value        = var.enable_logical_replication ? "1" : "0"
    apply_method = "pending-reboot"
  }

  # GCP 보안 진단(Allows unencrypted direct connections) 대응 — GCP Cloud SQL(gcp-modules/cloudsql/main.tf)
  # 쪽과 통일. 이것도 rds.logical_replication 과 같은 정적 파라미터라 반영되려면
  # 재부팅이 필요하다(Multi-AZ 페일오버 동반 가능) — apply만으로는 안 켜진다.
  # ledger/accounts 앱 쪽 JDBC/psycopg2 URL에 sslmode=require 를 같이 넣어둬야
  # 이 값이 켜진 뒤에도 연결이 끊기지 않는다(gitops/03_manifests/overlays/eks/{ledger,accounts}).
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.project_name}-postgres16"
  }
}


# PostgreSQL RDS
# PostgreSQL 인스턴스. SG 는 같은 모듈의 security.tf 가 만든 것을 쓰고,
# 마스터 비밀번호는 AWS 가 Secrets Manager 에 만들어 관리한다(manage_master_user_password).
# 주의 — skip_final_snapshot = true 라 삭제 시 최종 스냅샷이 남지 않는다.
resource "aws_db_instance" "main" {
  identifier = var.db_identifier

  # Database
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username
  port     = 5432

  # Master password is generated and managed by AWS Secrets Manager
  manage_master_user_password = true

  # Storage
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = true

  # Parameter Group
  parameter_group_name = aws_db_parameter_group.main.name

  # Backup
  backup_retention_period  = var.backup_retention_period
  delete_automated_backups = true
  skip_final_snapshot      = true
  copy_tags_to_snapshot    = true

  # Version / Apply
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Logs
  enabled_cloudwatch_logs_exports = [
    "postgresql"
  ]


  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period

  # Enhanced Monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Deletion Protection
  deletion_protection = false

  tags = {
    Name = var.db_identifier
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_monitoring,
    aws_cloudwatch_log_group.rds_os_metrics
  ]
}

# 향상된 모니터링이 OS 지표를 쓰는 로그 그룹. 이름이 AWS 고정이라 접두사를 못 붙인다.
# 계정·리전당 하나뿐이라 다른 스택이 이미 갖고 있으면 count = 0 으로 건너뛴다.
resource "aws_cloudwatch_log_group" "rds_os_metrics" {
  count = var.create_os_metrics_log_group ? 1 : 0

  name              = "RDSOSMetrics"
  retention_in_days = var.enhanced_monitoring_log_retention_days

  tags = {
    Name = "RDSOSMetrics"
  }
}

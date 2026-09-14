# =========================================================
# AWS DMS — RDS(AWS) → Cloud SQL(GCP) 연속 복제
#
# 설계 배경: DB 설계안 카탈로그의 AS-2(관리형 DB + CDC 연속 복제).
# GCP DMS 가 아니라 AWS DMS 를 쓰는 이유는 페일백 경로가 같은 도구 안에 있어서다.
# GCP DMS 는 승격이 비가역이라 DR 리허설을 반복할 수 없다.
#
# 구조상 주의할 점
#  - PostgreSQL 논리 복제는 DB 단위다. accounts · ledger 각각 엔드포인트·태스크가 필요하다
#  - 대상 Cloud SQL 은 복제본이 아니라 평범한 쓰기 가능 인스턴스다. 승격 단계가 없다
#  - 시퀀스는 복제되지 않는다. 페일오버 런북에 setval 이 반드시 들어간다
# =========================================================

# 복제 인스턴스가 들어갈 서브넷. private 서브넷을 쓰는 이유는
# aws-modules/rds 의 SG 가 private 서브넷 CIDR 로 5432 를 이미 열어두기 때문이다.
# 여기에 두면 RDS SG 를 건드리지 않아도 소스 접속이 통한다.
resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "${var.project_name}-dms-subnet-group"
  replication_subnet_group_description = "DMS replication instance subnets"
  subnet_ids                           = var.subnet_ids

  tags = {
    Name = "${var.project_name}-dms-subnet-group"
  }
}


# 복제 인스턴스 전용 SG.
# 인바운드 규칙이 없다 — DMS 는 자기가 소스·대상으로 나가기만 한다.
resource "aws_security_group" "dms" {
  name        = "${var.project_name}-dms-sg"
  description = "AWS DMS replication instance"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-dms-sg"
  }
}

# 소스 RDS(같은 VPC)와 대상 Cloud SQL(VPN 너머)로 나가는 아웃바운드.
resource "aws_vpc_security_group_egress_rule" "dms_postgres" {
  for_each = toset(concat([var.vpc_cidr], var.gcp_cidrs))

  security_group_id = aws_security_group.dms.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"

  description = "PostgreSQL to ${each.value}"
}

# CloudWatch 로그 전송 등 AWS API 호출용.
resource "aws_vpc_security_group_egress_rule" "dms_https" {
  security_group_id = aws_security_group.dms.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  description = "AWS API (CloudWatch logs)"
}


# 복제 인스턴스. 관리형 EC2 한 대다.
# PostgreSQL 16 소스라 3.5.x 면 충분하다
# (3.5.4 이상 제약은 PostgreSQL 17·18 소스에만 걸린다).
resource "aws_dms_replication_instance" "main" {
  replication_instance_id    = "${var.project_name}-dms"
  replication_instance_class = var.instance_class
  engine_version             = var.engine_version

  allocated_storage = var.allocated_storage

  # 대기 복제본을 두면 비용이 두 배다. DR 복제 자체는 재시작이 가능하므로 끈다.
  multi_az = false

  publicly_accessible         = false
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids      = [aws_security_group.dms.id]

  apply_immediately          = true
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-dms"
  }
}


# =========================================================
# 엔드포인트 — DB 마다 소스·대상 한 쌍
# PostgreSQL 커넥션은 DB 하나에 묶이므로 accounts · ledger 를 하나로 묶을 수 없다.
# =========================================================

resource "aws_dms_endpoint" "source" {
  for_each = var.databases

  endpoint_id   = "${var.project_name}-src-${each.key}"
  endpoint_type = "source"
  engine_name   = "postgres"

  server_name   = var.source_host
  port          = 5432
  database_name = each.value.source_db
  username      = var.source_username
  password      = var.source_password

  ssl_mode = "require"

  tags = {
    Name = "${var.project_name}-src-${each.key}"
  }
}

resource "aws_dms_endpoint" "target" {
  for_each = var.databases

  endpoint_id   = "${var.project_name}-tgt-${each.key}"
  endpoint_type = "target"
  engine_name   = "postgres"

  server_name   = var.target_host
  port          = 5432
  database_name = each.value.target_db
  username      = var.target_username
  password      = var.target_password

  ssl_mode = "require"

  # 이 설정이 없으면 전체 적재가 외래 키 위반으로 실패한다.
  # DMS 는 테이블을 하나씩 옮기고 순서를 보장하지 않는데, 대상에는
  # contacts.username 이 users.username 을 참조하는 외래 키가 이미 심어져 있다.
  # session_replication_role = replica 로 두면 FK 트리거를 우회한다.
  extra_connection_attributes = "AfterConnectScript=SET session_replication_role = replica"

  tags = {
    Name = "${var.project_name}-tgt-${each.key}"
  }
}


# =========================================================
# 복제 태스크
#
# 운영 주의 — 대부분의 인자를 변경하면 실행 중인 태스크가 중지된다.
# 중지된 태스크는 복제 슬롯을 붙든 채로 남고, 그러면 소스 RDS 에
# 소비되지 않은 WAL 이 계속 쌓인다. 아래 알람이 그걸 잡는다.
# =========================================================

resource "aws_dms_replication_task" "main" {
  for_each = var.databases

  replication_task_id      = "${var.project_name}-task-${each.key}"
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source[each.key].endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target[each.key].endpoint_arn

  migration_type = "full-load-and-cdc"

  # 대상 스키마는 GitOps 의 db-bootstrap Job 이 미리 심는다.
  # DMS 가 스스로 만드는 테이블은 기본 구조뿐이라 인덱스 · FK · RULE · 시퀀스가 빠진다.
  # 그래서 TargetTablePrepMode 를 DO_NOTHING 으로 둔다.
  replication_task_settings = jsonencode({
    TargetMetadata = {
      TargetSchema             = ""
      SupportLobs              = true
      FullLobMode              = false
      LobChunkSize             = 64
      LimitedSizeLobMode       = true
      LobMaxSize               = 32
      BatchApplyEnabled        = false
      ParallelLoadThreads      = 0
      TaskRecoveryTableEnabled = false
    }
    FullLoadSettings = {
      TargetTablePrepMode             = "DO_NOTHING"
      CreatePkAfterFullLoad           = false
      StopTaskCachedChangesApplied    = false
      StopTaskCachedChangesNotApplied = false
      MaxFullLoadSubTasks             = 8
      TransactionConsistencyTimeout   = 600
      CommitRate                      = 10000
    }
    Logging = {
      EnableLogging = true
    }
    ControlTablesSettings = {
      ControlSchema               = "dms_control"
      HistoryTimeslotInMinutes    = 5
      HistoryTableEnabled         = true
      StatusTableEnabled          = true
      SuspendedTablesTableEnabled = true
    }
    ErrorBehavior = {
      DataErrorPolicy          = "LOG_ERROR"
      TableErrorPolicy         = "SUSPEND_TABLE"
      RecoverableErrorCount    = -1
      RecoverableErrorInterval = 5
      ApplyErrorDeletePolicy   = "IGNORE_RECORD"
      FailOnNoTablesCaptured   = true
    }
  })

  # public 스키마 전체를 옮긴다. 앱 테이블이 전부 public 에 있다.
  table_mappings = jsonencode({
    rules = [
      {
        "rule-type" = "selection"
        "rule-id"   = "1"
        "rule-name" = "select-public"
        "object-locator" = {
          "schema-name" = "public"
          "table-name"  = "%"
        }
        "rule-action" = "include"
        "filters"     = []
      }
    ]
  })

  start_replication_task = var.start_tasks

  tags = {
    Name = "${var.project_name}-task-${each.key}"
  }
}


# =========================================================
# 알람 — DR 에서 이게 본체다
# 복제가 멈춘 것을 모르고 두면 소스 RDS 디스크가 WAL 로 찬다.
# =========================================================

# 대상 적용 지연. 이 값이 곧 실측 RPO 다.
resource "aws_cloudwatch_metric_alarm" "cdc_latency_target" {
  for_each = var.databases

  alarm_name          = "${var.project_name}-dms-${each.key}-cdc-latency-target"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CDCLatencyTarget"
  namespace           = "AWS/DMS"
  period              = 60
  statistic           = "Average"
  threshold           = var.cdc_latency_threshold_seconds

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
    ReplicationTaskIdentifier     = aws_dms_replication_task.main[each.key].replication_task_id
  }

  alarm_description  = "복제 지연이 RPO 목표를 넘었다. 이 값이 실측 RPO 다."
  treat_missing_data = "breaching"

  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns
}

# 소스 RDS 의 남은 스토리지.
# 복제가 멈춰 WAL 이 쌓이면 여기서 먼저 드러난다. DR 구성의 최대 사고 지점이다.
resource "aws_cloudwatch_metric_alarm" "source_free_storage" {
  alarm_name          = "${var.project_name}-rds-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.free_storage_threshold_bytes

  dimensions = {
    DBInstanceIdentifier = var.source_db_identifier
  }

  alarm_description = "소스 RDS 여유 스토리지 부족. 복제 슬롯이 WAL 을 붙들고 있는지 확인할 것."

  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns
}

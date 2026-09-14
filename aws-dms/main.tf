# =========================================================
# aws-dms — RDS(AWS) → Cloud SQL(GCP) 연속 복제
#
# apply 순서상 aws-core · aws-rds 직후다. 다만 실제로 동작하려면
# GCP 쪽(gcp-core, gcp-cloudsql)과 VPN(net-link)이 먼저 서 있어야 한다.
# 런북 §3 의 순서를 따를 것.
#
# 참조 방식이 다른 루트와 다르다
#  - AWS 쪽(aws-core, aws-rds)은 기존 관례대로 terraform_remote_state
#  - GCP 쪽은 tfvars 로 받는다. GCP 루트 구조가 아직 유동적이라
#    remote_state 로 묶으면 리팩터링 때마다 이 루트가 깨진다.
#    GCP 구조가 안정되면 remote_state 로 승격한다.
# =========================================================

data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "rds" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/rds/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# RDS 마스터 비밀번호는 AWS 가 Secrets Manager 에 만들어 관리한다
# (aws_db_instance.manage_master_user_password = true).
# 그 시크릿을 읽어 소스 엔드포인트 자격증명으로 쓴다. tfvars 에 비밀번호를 적지 않는다.
data "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = data.terraform_remote_state.rds.outputs.master_user_secret_arn
}

locals {
  rds_master = jsondecode(data.aws_secretsmanager_secret_version.rds_master.secret_string)
}

module "dms" {
  source = "../aws-modules/dms"

  project_name = "boa"

  vpc_id     = data.terraform_remote_state.core.outputs.vpc_id
  vpc_cidr   = data.terraform_remote_state.core.outputs.vpc_cidr
  subnet_ids = data.terraform_remote_state.core.outputs.private_subnet_ids

  # VPN 너머 GCP 대역. gcp-core 의 서브넷 대역과 일치해야 한다.
  gcp_cidrs = var.gcp_cidrs

  instance_class    = "dms.t3.medium"
  engine_version    = "3.5.3"
  allocated_storage = 50

  # PostgreSQL 논리 복제는 DB 단위다. 두 DB 는 각각 슬롯·스트림을 갖는다.
  databases = {
    accounts = {
      source_db = "accounts"
      target_db = "accounts"
    }
    ledger = {
      source_db = "ledger"
      target_db = "ledger"
    }
  }

  source_host          = data.terraform_remote_state.rds.outputs.db_address
  source_username      = local.rds_master["username"]
  source_password      = local.rds_master["password"]
  source_db_identifier = data.terraform_remote_state.rds.outputs.db_instance_identifier

  target_host     = var.cloudsql_private_ip
  target_username = var.cloudsql_dms_username
  target_password = var.cloudsql_dms_password

  # 기본 false. VPN 연결과 대상 스키마 준비를 확인한 뒤 true 로 바꿔 다시 apply 한다.
  start_tasks = var.start_tasks

  # RPO 목표 5분보다 낮게 잡아 여유를 둔다.
  cdc_latency_threshold_seconds = 180
  free_storage_threshold_bytes  = 5368709120

  alarm_sns_topic_arns = var.alarm_sns_topic_arns
}

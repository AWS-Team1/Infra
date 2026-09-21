# aws-core 가 만든 네트워크를 읽는다. 이 루트는 aws-eks 를 참조하지 않는다.
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/test/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

module "rds" {
  source = "../aws-modules/rds"

  project_name = "boa-test"

  db_identifier = "boa-test-postgres"
  db_name       = "boadb"
  db_username   = "boa_test_admin"

  engine_version = "16.14"
  instance_class = "db.t4g.micro"

  allocated_storage     = 30
  max_allocated_storage = 100

  vpc_id               = data.terraform_remote_state.core.outputs.vpc_id
  private_subnet_cidrs = data.terraform_remote_state.core.outputs.private_subnet_cidrs
  db_subnet_ids        = data.terraform_remote_state.core.outputs.db_subnet_ids

  backup_retention_period                = 7
  monitoring_interval                    = 60
  performance_insights_retention_period  = 7
  enhanced_monitoring_log_retention_days = 7

  # RDSOSMetrics 는 계정·리전 공용 고정 이름. 기존 스택이 이미 보유 중이라 생성하지 않는다.
  create_os_metrics_log_group = false

  # AWS DMS 의 CDC 전제 조건. 정적 파라미터라 apply 후 인스턴스 재부팅이 필요하다.
  # 재부팅 전까지 파라미터 상태는 pending-reboot 로 남고 DMS 는 슬롯을 못 만든다.
  enable_logical_replication = true
}

data "aws_route53_zone" "private" {
  name         = "test.boa.internal."
  private_zone = true
  vpc_id       = data.terraform_remote_state.core.outputs.vpc_id
}

resource "aws_route53_record" "database" {
  zone_id = data.aws_route53_zone.private.zone_id
  name    = "db.test.boa.internal"
  type    = "CNAME"
  ttl     = 60
  records = [module.rds.db_address]
}

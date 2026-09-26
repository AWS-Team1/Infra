# =========================================================
# aws-observability — 관측 스택의 AWS 측 리소스
#
# 의존 관계 (1단 평면 유지)
#   aws-core → VPC
#   aws-eks  → 클러스터 이름 (Pod Identity 연결 대상)
#   aws-ops  → ops ALB 의 HTTPS 리스너 (Grafana 규칙을 붙일 곳)
#
# 이 루트는 aws-rds · aws-cache · aws-dms 를 참조하지 않는다.
#
# 적용 순서 — aws-core → aws-eks → aws-ops → (여기)
#   앞의 셋이 없으면 remote state 읽기에서 멈춘다.
# =========================================================

data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = module.environment.state_bucket
    key    = "aws/core/terraform.tfstate"
    region = module.environment.aws_region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = module.environment.state_bucket
    key    = "aws/eks/terraform.tfstate"
    region = module.environment.aws_region
  }
}

data "terraform_remote_state" "ops" {
  backend = "s3"

  config = {
    bucket = module.environment.state_bucket
    key    = "aws/ops/terraform.tfstate"
    region = module.environment.aws_region
  }
}

module "observability" {
  source = "../aws-modules/observability"

  project_name = module.environment.project_name
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  region       = module.environment.aws_region
  vpc_id       = data.terraform_remote_state.core.outputs.vpc_id

  # gitops 의 03_manifests/base/observability/namespace.yaml 과 일치해야 한다.
  observability_namespace   = "monitoring"
  collector_service_account = "otel-collector"
  grafana_service_account   = "grafana"

  # 로그 보존 — 컨트롤 플레인 로그가 30일이므로 앱 로그도 같이 맞춘다.
  # 감사 기록만 90일로 길게 둔다.
  application_log_retention_days = 30
  audit_findings_retention_days  = 90

  enable_telemetry_archive = var.enable_telemetry_archive

  enable_log_data_protection = var.enable_log_data_protection

  # ops-alb 모듈이 100번대를 ArgoCD 에 쓰고 200번대를 관측성용으로 비워 두었다.
  grafana_host                   = module.environment.grafana_host
  grafana_target_port            = 3000
  grafana_listener_rule_priority = 200
  ops_alb_https_listener_arn     = data.terraform_remote_state.ops.outputs.ops_alb_https_listener_arn
  ops_alb_security_group_id      = data.terraform_remote_state.ops.outputs.ops_alb_security_group_id
  private_subnet_cidrs           = data.terraform_remote_state.core.outputs.private_subnet_cidrs

  secret_path_prefix = "/${module.environment.project_name}/observability"
}


# ===================================================
# ROUTE53 — Grafana
# ===================================================

# aws-ops 가 argocd 레코드를 소유하는 것과 같은 방식이다.
# 존은 조회만 하고 만들지 않는다.
data "aws_route53_zone" "public" {
  name         = "${module.environment.public_zone_name}."
  private_zone = false
}

resource "aws_route53_record" "grafana" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = module.environment.grafana_host
  type    = "A"

  alias {
    name                   = data.terraform_remote_state.ops.outputs.ops_alb_dns_name
    zone_id                = data.terraform_remote_state.ops.outputs.ops_alb_zone_id
    evaluate_target_health = true
  }
}

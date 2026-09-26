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
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/eks/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "ops" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/ops/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

module "observability" {
  source = "../aws-modules/observability"

  project_name = "boa"
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  region       = "ap-northeast-2"
  vpc_id       = data.terraform_remote_state.core.outputs.vpc_id

  # gitops 의 03_manifests/base/observability/namespace.yaml 과 일치해야 한다.
  observability_namespace   = "monitoring"
  collector_service_account = "otel-collector"
  grafana_service_account   = "grafana"

  # gitops 의 boa-external-secrets Application(overlays/eks/applications/
  # observability-platform.yaml)의 destination.namespace · serviceAccount.name
  # 과 일치해야 한다.
  eso_namespace       = "external-secrets"
  eso_service_account = "external-secrets"

  # 로그 보존 — 컨트롤 플레인 로그가 30일이므로 앱 로그도 같이 맞춘다.
  # 감사 기록만 90일로 길게 둔다.
  application_log_retention_days = 30
  audit_findings_retention_days  = 90

  enable_telemetry_archive          = var.enable_telemetry_archive
  telemetry_archive_transition_days = 30
  telemetry_archive_expiration_days = 365

  enable_log_data_protection = var.enable_log_data_protection

  # ops-alb 모듈이 100번대를 ArgoCD 에 쓰고 200번대를 관측성용으로 비워 두었다.
  grafana_host                   = var.grafana_host
  grafana_target_port            = 3000
  grafana_listener_rule_priority = 200
  ops_alb_https_listener_arn     = data.terraform_remote_state.ops.outputs.ops_alb_https_listener_arn

  secret_path_prefix = "/boa/observability"
}


# ===================================================
# SECRETS MANAGER — 와탭 라이선스 키 · Grafana 관리자 비밀번호
# ===================================================

# 값은 Terraform 이 넣지 않는다. 껍데기만 만들고 사람이 콘솔이나 CLI 로 채운다.
# tfvars 나 state 에 라이선스 키가 들어가지 않게 하려는 것이다 —
# state 는 S3 에 암호화되어 있지만 plan 출력과 CI 로그에는 남는다.
#
# 채우는 명령은 outputs.tf 의 secret_fill_commands 가 그대로 출력한다.
resource "aws_secretsmanager_secret" "whatap" {
  name        = "/boa/observability/whatap"
  description = "WhaTap license keys. Values are set out-of-band, never by Terraform."

  # 실습 환경이라 짧게 둔다. 지운 뒤 같은 이름을 바로 다시 쓸 수 있다.
  recovery_window_in_days = 0

  tags = {
    Name = "boa-observability-whatap"
  }
}

resource "aws_secretsmanager_secret" "grafana" {
  name        = "/boa/observability/grafana"
  description = "Grafana admin credentials. Values are set out-of-band, never by Terraform."

  recovery_window_in_days = 0

  tags = {
    Name = "boa-observability-grafana"
  }
}


# ===================================================
# ROUTE53 — Grafana
# ===================================================

# aws-ops 가 argocd 레코드를 소유하는 것과 같은 방식이다.
# 존은 조회만 하고 만들지 않는다.
data "aws_route53_zone" "public" {
  # HARD-CODED: ACM 인증서(*.bespinglobal.site)와 ops ALB Host 조건에 맞는 존이다.
  name         = "bespinglobal.site."
  private_zone = false
}

resource "aws_route53_record" "grafana" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.grafana_host
  type    = "A"

  alias {
    name                   = data.terraform_remote_state.ops.outputs.ops_alb_dns_name
    zone_id                = data.terraform_remote_state.ops.outputs.ops_alb_zone_id
    evaluate_target_health = true
  }
}

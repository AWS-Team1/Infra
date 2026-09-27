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
#
# Terraform이 만들지 않는다. 콘솔에서 이미 만든 /boa/observability/whatap ·
# /boa/observability/grafana 를 그대로 쓰기로 결정했다(2026-09-26, ECR과
# 같은 패턴 — AGENTS.md 규칙 4). 여기서 aws_secretsmanager_secret 리소스로
# 다시 선언하면 콘솔에서 만든 것과 이름이 겹쳐 apply 시 ResourceExistsException
# 이 난다. IAM 쪽은 이름이 아니라 secret_path_prefix("/boa/observability")
# 와일드카드로 권한을 주므로, 누가 만들었는지와 무관하게 그대로 동작한다.


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

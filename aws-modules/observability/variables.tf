variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "cluster_name" {
  description = "Pod Identity 연결 대상 EKS 클러스터. ARN 조립에도 쓴다"
  type        = string
}

variable "region" {
  description = "ARN 조립과 로그 그룹 경로에 쓴다"
  type        = string
}

variable "vpc_id" {
  description = "Grafana 대상 그룹을 만들 VPC"
  type        = string
}


# ---------------------------------------------------------
# 네임스페이스 · 서비스어카운트
# ---------------------------------------------------------
# gitops 의 03_manifests/base/observability/namespace.yaml 과 반드시 일치해야 한다.
# 어긋나면 Pod Identity 가 연결되지 않고 수집기가 자격증명 없이 뜬다.

variable "observability_namespace" {
  description = "수집기·Grafana 가 들어갈 네임스페이스"
  type        = string
  default     = "monitoring"
}

variable "collector_service_account" {
  description = "OpenTelemetry 수집기 게이트웨이의 ServiceAccount 이름"
  type        = string
  default     = "otel-collector"
}

variable "grafana_service_account" {
  description = "Grafana 의 ServiceAccount 이름"
  type        = string
  default     = "grafana"
}


# ---------------------------------------------------------
# 로그 보존
# ---------------------------------------------------------

variable "application_log_retention_days" {
  description = "앱 로그 그룹 보존 기간"
  type        = number
  default     = 30
}

variable "audit_findings_retention_days" {
  description = "데이터 보호 정책의 마스킹 감지 기록 보존 기간. 감사 증적이므로 앱 로그보다 길게 둔다"
  type        = number
  default     = 90
}


# ---------------------------------------------------------
# 텔레메트리 장기 보관 (수집데이터 백업)
# ---------------------------------------------------------

variable "enable_telemetry_archive" {
  description = "false 면 S3 버킷과 수집기의 s3 쓰기 권한을 만들지 않는다"
  type        = bool
  default     = true
}

variable "telemetry_archive_transition_days" {
  description = "STANDARD → STANDARD_IA 전환 일수"
  type        = number
  default     = 30
}

variable "telemetry_archive_expiration_days" {
  description = "객체 만료 일수. 0 이면 만료시키지 않는다"
  type        = number
  default     = 365
}


# ---------------------------------------------------------
# 민감정보 마스킹 (CloudWatch Logs 데이터 보호 정책)
# ---------------------------------------------------------

variable "enable_log_data_protection" {
  description = "false 면 데이터 보호 정책을 붙이지 않는다. 오탐이 많을 때 끄고 재조정한다"
  type        = bool
  default     = true
}

# 정규식은 CloudWatch Logs 가 아니라 이 모듈이 정의한다. Bank of Anthos 의
# 계좌번호는 10자리, 라우팅번호는 9자리 순수 숫자이므로 관리형 식별자로는 안 잡힌다.
#
# 주의 — 자리수만 보는 규칙이라 오탐이 구조적으로 발생한다. epoch 밀리초(13자리)는
# 피하지만 epoch 초(10자리)와 계좌번호는 구분되지 않는다. 실제 로그를 며칠 받아 본 뒤
# 접두사·키 이름을 포함한 규칙으로 좁히는 것이 전제다(변경 내역의 미결 항목 참조).
variable "custom_data_identifiers" {
  description = "이름 → 정규식. CloudWatch Logs 커스텀 데이터 식별자로 등록된다"
  type        = map(string)

  default = {
    # 10자리 계좌번호. 앞뒤가 숫자가 아닐 때만 잡는다.
    BoaAccountId = "(?<![0-9])[0-9]{10}(?![0-9])"

    # 9자리 라우팅번호(LOCAL_ROUTING_NUM).
    BoaRoutingNumber = "(?<![0-9])[0-9]{9}(?![0-9])"

    # RS256 JWT. userservice 가 발급하고 5개 서비스가 헤더로 받는다.
    BoaJwtToken = "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}"
  }
}

variable "managed_data_identifiers" {
  description = "AWS 관리형 데이터 식별자 ARN 목록"
  type        = list(string)

  default = [
    "arn:aws:dataprotection::aws:data-identifier/EmailAddress",
    "arn:aws:dataprotection::aws:data-identifier/CreditCardNumber",
  ]
}


# ---------------------------------------------------------
# Grafana 노출 (ops ALB 에 붙는다)
# ---------------------------------------------------------

variable "grafana_host" {
  description = "Grafana 호스트명. HTTPS 리스너의 host-header 조건과 Route53 레코드에 함께 쓴다"
  type        = string
}

variable "grafana_target_port" {
  description = "Grafana 파드의 대상 포트"
  type        = number
  default     = 3000
}

# aws-ops 의 ops-alb 모듈이 100번대를 ArgoCD 에 쓰고 200번대를 관측성용으로 비워 두었다.
variable "grafana_listener_rule_priority" {
  description = "ops ALB HTTPS 리스너 규칙 우선순위"
  type        = number
  default     = 200
}

variable "ops_alb_https_listener_arn" {
  description = "aws-ops 가 출력하는 ops ALB 의 HTTPS 리스너 ARN"
  type        = string
}


# ---------------------------------------------------------
# 시크릿
# ---------------------------------------------------------

variable "secret_path_prefix" {
  description = "수집기·Grafana 가 읽을 Secrets Manager 경로 접두사"
  type        = string
  default     = "/boa/observability"
}

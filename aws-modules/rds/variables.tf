variable "project_name" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "engine_version" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "max_allocated_storage" {
  type = number
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "backup_retention_period" {
  type = number
}

variable "monitoring_interval" {
  type = number
}

variable "performance_insights_retention_period" {
  type = number
}

variable "enhanced_monitoring_log_retention_days" {
  type = number
}

# RDSOSMetrics 로그 그룹은 RDS 향상된 모니터링이 쓰는 계정·리전 공용 고정 이름이다.
# 이미 다른 스택이 만들어 둔 경우 false 로 두어 생성을 건너뛴다.
variable "create_os_metrics_log_group" {
  description = "RDSOSMetrics CloudWatch 로그 그룹을 이 스택이 생성할지 여부"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "db Security Group 을 만들 VPC"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "5432 인바운드를 허용할 프라이빗 서브넷 CIDR"
  type        = list(string)
}

# AWS DMS 의 CDC 가 논리 복제 슬롯을 만들려면 필요하다.
# 켜는 순간이 아니라 "다음 재부팅"에 반영된다(정적 파라미터).
variable "enable_logical_replication" {
  description = "rds.logical_replication 활성화 여부. DMS CDC 의 전제 조건"
  type        = bool
  default     = false
}


# ---------------------------------------------------------
# 감사 로깅 (관측·보안 파트 추가)
# ---------------------------------------------------------
# 기본값은 전부 "현재 동작 유지"다. 아래 변수를 건드리지 않으면
# terraform plan 에 변화가 나타나지 않는다.
#
# 왜 별도 변수인가 — pgaudit 와 log_min_duration_statement=0 은 로그량과
# CloudWatch 수집 요금에 직접 영향을 준다. 기본값으로 켜면 모르는 사이에
# 비용이 늘고, 되돌릴 때 재부팅이 필요하다.

variable "log_min_duration_statement_ms" {
  description = "이 시간(ms)을 넘는 쿼리를 로그로 남긴다. 0 이면 모든 쿼리. -1 이면 끈다"
  type        = number
  default     = 1000
}

# pgaudit 는 shared_preload_libraries 에 들어가야 동작한다. 그 파라미터는 정적이라
# 값을 바꾸면 인스턴스 재부팅이 필요하고, Multi-AZ 에서는 AZ 페일오버를 동반한다.
variable "enable_pgaudit" {
  description = "pgaudit 확장을 shared_preload_libraries 에 넣는다. 정적 파라미터라 재부팅 필요"
  type        = bool
  default     = false
}

variable "pgaudit_log_classes" {
  description = "pgaudit.log 값. 쉼표 없이 공백 없는 문자열로 넣는다. 예: ddl,role,write"
  type        = string
  default     = "ddl,role"
}

# 쿼리 로그에 바인딩 파라미터가 그대로 찍히면 계좌번호가 로그로 새어 나간다.
# 0 은 "파라미터를 기록하지 않는다"다. 늘리려면 CloudWatch Logs 데이터 보호
# 정책(aws-modules/observability)이 먼저 붙어 있어야 한다.
variable "log_parameter_max_length" {
  description = "쿼리 로그에 남길 바인딩 파라미터 최대 길이. 0 = 기록하지 않음"
  type        = number
  default     = 0
}

variable "log_statement" {
  description = "none / ddl / mod / all. all 은 로그량이 폭발하므로 감사 기간에만 쓴다"
  type        = string
  default     = "none"
}

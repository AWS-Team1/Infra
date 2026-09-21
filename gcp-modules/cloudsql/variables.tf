variable "project_name" {
  type = string
}

variable "instance_name" {
  description = "Cloud SQL 인스턴스 이름. 한번 쓴 이름은 삭제 후 일정 기간 재사용이 막힌다"
  type        = string
}

# AWS RDS 가 postgres 16.14 다. 메이저를 맞춰야 논리 복제가 안전하다.
variable "database_version" {
  description = "Cloud SQL PostgreSQL 버전"
  type        = string
  default     = "POSTGRES_16"
}

variable "region" {
  type = string
}

variable "tier" {
  description = "머신 타입. Pilot Light 라 소형으로 둔다"
  type        = string
  default     = "db-custom-1-3840"
}

# ZONAL = 단일 영역(저렴), REGIONAL = HA. 대기 단계에서는 ZONAL 로 두고
# 페일오버 후 REGIONAL 로 올리는 것이 Pilot Light 의 취지에 맞다.
variable "availability_type" {
  type    = string
  default = "ZONAL"
}

variable "disk_size" {
  type    = number
  default = 20
}

variable "transaction_log_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "network_id" {
  description = "gcp-core 가 만든 VPC. 사설 IP 할당 대상"
  type        = string
}

variable "psa_connection" {
  description = "private services access 연결. 순서 보장용으로 받는다"
  type        = string
}

variable "app_database_names" {
  description = "생성할 논리 DB 목록. AWS 쪽 accounts·ledger 와 같은 이름이어야 DMS 매핑이 단순하다"
  type        = list(string)
}

variable "dms_username" {
  description = "AWS DMS 대상 엔드포인트가 쓸 계정"
  type        = string
  default     = "dms_writer"
}

variable "dms_password" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "accounts_username" {
  type = string
}

variable "accounts_password" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "ledger_username" {
  type = string
}

variable "ledger_password" {
  type      = string
  sensitive = true
  ephemeral = true
}

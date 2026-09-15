variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

# ---------- 네트워크 ----------

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "소스 RDS 가 있는 VPC CIDR. 아웃바운드 5432 허용에 쓴다"
  type        = string
}

# private 서브넷을 넣는다. RDS SG 가 private CIDR 로 5432 를 이미 열어두고 있어
# 여기에 두면 RDS 쪽을 손대지 않아도 된다.
variable "subnet_ids" {
  description = "복제 인스턴스가 들어갈 서브넷(서로 다른 AZ 2개 이상)"
  type        = list(string)
}

variable "gcp_cidrs" {
  description = "VPN 너머 GCP 대역. 대상 Cloud SQL 로 나가는 아웃바운드에 쓴다"
  type        = list(string)
}

# ---------- 복제 인스턴스 ----------

variable "instance_class" {
  description = "복제 인스턴스 클래스. 이 워크로드는 소형으로 충분하다"
  type        = string
  default     = "dms.t3.medium"
}

variable "engine_version" {
  description = "DMS 엔진 버전. PostgreSQL 16 소스는 3.5.x 로 충분하다"
  type        = string
  default     = "3.5.3"
}

variable "allocated_storage" {
  description = "복제 인스턴스 스토리지(GB). 전송 중 변경분과 로그가 여기 쌓인다"
  type        = number
  default     = 50
}

# ---------- 복제 대상 ----------

# 키가 태스크 이름에 들어간다. accounts · ledger 두 개다.
variable "databases" {
  description = "복제할 DB 매핑. 키는 식별자, 값은 소스·대상 DB 이름"
  type = map(object({
    source_db = string
    target_db = string
  }))
}

# ---------- 소스 (AWS RDS) ----------

variable "source_host" {
  description = "RDS 엔드포인트 주소"
  type        = string
}

variable "source_username" {
  type = string
}

variable "source_password" {
  description = "RDS 마스터 비밀번호. Secrets Manager 값을 tfvars 로 넘긴다"
  type        = string
  sensitive   = true
}

variable "source_db_identifier" {
  description = "FreeStorageSpace 알람의 디멘션에 쓴다"
  type        = string
}

# ---------- 대상 (GCP Cloud SQL) ----------

variable "target_host" {
  description = "Cloud SQL 사설 IP. gcp-cloudsql 의 private_ip_address 출력값"
  type        = string
}

variable "target_username" {
  type    = string
  default = "dms_writer"
}

variable "target_password" {
  type      = string
  sensitive = true
}

# ---------- 운영 ----------

# false 로 두면 태스크가 생성만 되고 시작하지 않는다.
# VPN·스키마 준비가 끝난 것을 확인한 뒤 true 로 바꿔 apply 하는 것을 권한다.
variable "start_tasks" {
  description = "생성 직후 복제 태스크를 시작할지 여부"
  type        = bool
  default     = false
}

variable "cdc_latency_threshold_seconds" {
  description = "복제 지연 알람 임계값(초). RPO 목표 5분보다 낮게 잡는다"
  type        = number
  default     = 180
}

variable "free_storage_threshold_bytes" {
  description = "소스 RDS 여유 스토리지 알람 임계값(바이트). 기본 5GB"
  type        = number
  default     = 5368709120
}

variable "alarm_sns_topic_arns" {
  description = "알람 통지 대상 SNS 토픽. 비워두면 알람은 상태만 바뀐다"
  type        = list(string)
  default     = []
}

# GCP 쪽 값은 remote_state 가 아니라 tfvars 로 받는다.
# GCP 루트 구조가 아직 유동적이라 결합을 미룬다(main.tf 머리말 참고).
# 값은 gcp-core / gcp-cloudsql 의 output 에서 꺼내 넣는다.

variable "gcp_cidrs" {
  description = "VPN 너머 GCP 대역. gcp-core 의 서브넷 CIDR 과 일치해야 한다"
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "cloudsql_private_ip" {
  description = "대상 Cloud SQL 사설 IP. `terraform -chdir=../gcp-cloudsql output -raw private_ip_address`"
  type        = string
}

variable "cloudsql_dms_username" {
  description = "Cloud SQL 의 DMS 전용 계정"
  type        = string
  default     = "dms_writer"
}

variable "cloudsql_dms_password" {
  description = "Cloud SQL DMS 계정 비밀번호. gcp-cloudsql 에 넘긴 값과 같아야 한다"
  type        = string
  sensitive   = true
}

# 태스크 생성과 시작을 분리한다.
# VPN 연결과 대상 스키마 준비가 끝난 것을 확인한 뒤 true 로 바꿔 다시 apply 한다.
variable "start_tasks" {
  description = "복제 태스크를 생성 직후 시작할지 여부"
  type        = bool
  default     = false
}

variable "alarm_sns_topic_arns" {
  description = "복제 지연·스토리지 알람 통지 대상"
  type        = list(string)
  default     = []
}

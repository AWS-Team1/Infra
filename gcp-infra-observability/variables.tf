variable "gcp_project_id" {
  description = "Cloud Monitoring dashboard를 생성할 GCP 프로젝트 ID"
  type        = string
  default     = "kdt4-1-506106"
}

variable "region" {
  description = "대상 GCP 리소스의 기본 리전. Dashboard filter는 프로젝트 전체를 조회한다"
  type        = string
  default     = "asia-northeast2"
}

variable "dashboard_display_name" {
  description = "Cloud Monitoring에 표시할 GCP 관리형 인프라 dashboard 이름"
  type        = string
  default     = "boa-gcp-infrastructure"
}

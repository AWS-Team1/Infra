variable "enable_telemetry_archive" {
  description = "persistent root가 소유하는 텔레메트리 버킷에 수집기 쓰기 권한을 줄 것인가"
  type        = bool
  default     = true
}

variable "enable_log_data_protection" {
  description = "CloudWatch Logs 데이터 보호 정책(마스킹)을 붙일 것인가"
  type        = bool
  default     = true
}

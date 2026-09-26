variable "grafana_host" {
  description = "Grafana 접속 호스트명. ops ALB 리스너 규칙과 Route53 레코드에 함께 쓴다"
  type        = string
  default     = "grafana.bespinglobal.site"
}

variable "enable_telemetry_archive" {
  description = "텔레메트리 장기 보관 S3 버킷을 만들 것인가"
  type        = bool
  default     = true
}

variable "enable_log_data_protection" {
  description = "CloudWatch Logs 데이터 보호 정책(마스킹)을 붙일 것인가"
  type        = bool
  default     = true
}

variable "gcp_project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "gcp_region" {
  type    = string
  default = "asia-northeast2"
}

# 터널 4개의 사전 공유 키. 길이 8~64, 0 으로 시작 불가.
# 생성 예: openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
variable "tunnel_preshared_keys" {
  description = "VPN 연결별 터널 사전 공유 키 2개씩"
  type        = map(list(string))
  sensitive   = true
}

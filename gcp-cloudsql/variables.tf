variable "gcp_project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-northeast2"
}

# 비밀값은 terraform.tfvars 로 넘긴다. 저장소에 커밋하지 않는다.
variable "dms_password" {
  description = "AWS DMS 대상 엔드포인트가 쓸 계정 비밀번호"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "deletion_protection" {
  description = "평상시 true. 전체 철거 직전에만 false로 apply한다"
  type        = bool
  default     = true
}

variable "gcp_project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-northeast3"
}

# 비밀값은 terraform.tfvars 로 넘긴다. 저장소에 커밋하지 않는다.
variable "dms_password" {
  description = "AWS DMS 대상 엔드포인트가 쓸 계정 비밀번호"
  type        = string
  sensitive   = true
}

variable "app_password" {
  description = "애플리케이션 계정 비밀번호. AWS 쪽 app-password 와 같게 맞추면 페일오버가 단순해진다"
  type        = string
  sensitive   = true
}

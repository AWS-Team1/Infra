variable "gcp_project_id" {
  description = "GCP 프로젝트 ID. terraform.tfvars 로 넘긴다(저장소에 커밋하지 않는다)"
  type        = string
}

variable "region" {
  type    = string
  default = "asia-northeast2"
}

variable "project_name" {
  description = "Secrets Manager 경로 접두사"
  type        = string
}

variable "cluster_name" {
  description = "IAM 이름 접두사 및 cluster ARN 조립에 쓴다"
  type        = string
}

variable "region" {
  description = "ARN 조립에 쓴다"
  type        = string
}

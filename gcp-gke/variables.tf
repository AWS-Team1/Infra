variable "gcp_project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-northeast3"
}

# GKE 마스터에 접근을 허용할 대역. 운영자 IP 나 코드서버 IP 를 넣는다.
# AWS EKS 의 public_access_cidrs 와 같은 역할이다.
variable "master_authorized_cidrs" {
  description = "GKE 마스터 접근 허용 대역"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "gcp_project_id" {
  type    = string
  default = "kdt4-1-506106"
}

variable "region" {
  type    = string
  default = "asia-northeast2"
}

# GKE 마스터에 접근을 허용할 대역. 운영자 IP 나 코드서버 IP 를 넣는다.
# AWS EKS 의 public_access_cidrs 와 같은 역할이다.
variable "master_authorized_cidrs" {
  description = "GKE 마스터 접근 허용 대역"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "15.165.176.99/32"
    display_name = "code-server"
  }]
}

# 실행 중인 GitHub Actions runner IP. 워크플로가 실행마다 채워 master_authorized_cidrs 에 더한다.
# 이 변수만 덮어쓰므로 코드서버 대역은 CI apply 후에도 남는다.
variable "runner_authorized_cidrs" {
  description = "GKE 마스터 접근 허용 대역에 추가할 CI runner 대역"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

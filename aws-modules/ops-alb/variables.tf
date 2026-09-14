variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "vpc_id" {
  description = "대상 그룹과 SG 를 만들 VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "ALB 를 배치할 퍼블릭 서브넷. 최소 2개 AZ"
  type        = list(string)
}

# ALB 에서 파드로 나가는 아웃바운드를 여기로 제한한다.
# EKS 클러스터 SG 를 참조하지 않으므로 이 모듈이 aws-eks 를 알 필요가 없다.
variable "private_subnet_cidrs" {
  description = "ALB 아웃바운드를 허용할 대상 서브넷 CIDR"
  type        = list(string)
}

variable "certificate_domain" {
  description = "HTTPS 리스너에 붙일 ACM 인증서의 도메인. data 로 조회한다"
  type        = string
}

# 리스너 규칙의 Host 헤더 조건에 쓴다. DNS 레코드는 이 모듈이 만들지 않으므로
# 이 이름을 ALB 로 보내는 레코드는 밖에서 따로 잡아야 한다.
variable "argocd_host" {
  description = "ArgoCD 접속 호스트명. 리스너 규칙의 host-header 조건에 쓴다"
  type        = string
}

# argocd-server 컨테이너 포트. Service 포트(80)가 아니라 파드 포트다.
# TargetGroupBinding 이 파드 IP 를 이 포트로 등록한다.
variable "argocd_target_port" {
  description = "ArgoCD 파드의 대상 포트"
  type        = number
  default     = 8080
}

variable "ssl_policy" {
  description = "HTTPS 리스너의 TLS 정책"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  description = "true 면 콘솔·API 로 ALB 를 지울 수 없다"
  type        = bool
  default     = false
}

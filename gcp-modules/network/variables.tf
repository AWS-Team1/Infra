variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "region" {
  description = "GCP 리전. DR 자원은 일본 오사카 asia-northeast2에 둔다"
  type        = string
}

# ⚠️ AWS VPC 가 192.168.0.0/16 이다. 절대 겹치면 안 된다.
variable "subnet_cidr" {
  description = "GKE 노드 서브넷 CIDR"
  type        = string
}

variable "pods_cidr" {
  description = "GKE 파드용 secondary range"
  type        = string
}

variable "services_cidr" {
  description = "GKE 서비스용 secondary range"
  type        = string
}

# HA VPN 의 BGP 에서도 쓰인다. AWS 쪽 ASN 과 달라야 한다.
variable "cloud_router_asn" {
  description = "Cloud Router BGP ASN"
  type        = number
  default     = 64514
}

variable "aws_vpc_cidrs" {
  description = "VPN 너머 AWS 대역. 방화벽 source_ranges 에 들어간다"
  type        = list(string)
}

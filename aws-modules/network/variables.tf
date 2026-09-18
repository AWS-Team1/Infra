variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

# Karpenter 서브넷 탐색 태그(karpenter.sh/discovery)에 들어갈 값.
# eks 모듈의 cluster_name 과 반드시 같아야 한다.
variable "cluster_name" {
  description = "EKS cluster name used for karpenter.sh/discovery tag"
  type        = string
}

# 새로 생성할 VPC 의 IPv4 CIDR 이다.
variable "vpc_cidr" {
  description = "boa-vpc IPv4 CIDR"
  type        = string
}

variable "region" {
  description = "S3 Gateway Endpoint service name에 사용할 AWS 리전"
  type        = string
}

variable "availability_zones" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "db_subnet_cidrs" {
  type = list(string)
}

# ElastiCache 전용. 라우팅 테이블을 붙이지 않아 외부로 나가지 않는다.
variable "cache_subnet_cidrs" {
  type = list(string)
}

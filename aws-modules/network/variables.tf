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

# 기존 VPC 를 재사용한다. 이 모듈은 VPC 와 IGW 를 생성하지 않는다.
variable "vpc_id" {
  description = "재사용할 기존 VPC ID"
  type        = string
}

# 기존 S3 Gateway Endpoint. 새로 만드는 private route table 에 연결만 추가한다.
# 빈 문자열이면 연결하지 않는다.
variable "s3_gateway_endpoint_id" {
  description = "기존 S3 Gateway VPC Endpoint ID (없으면 빈 문자열)"
  type        = string
  default     = ""
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

# 프로젝트 이름
variable "project_name" {
  type = string
}

# Serverless Cache 이름
variable "cache_name" {
  type = string
}

# Valkey RBAC 사용자 이름
variable "user_name" {
  type = string
}

# Valkey RBAC 사용자 비밀번호. 호출자가 외부 Secret에서 읽어 전달한다.
variable "user_password" {
  type      = string
  sensitive = true
}

# ElastiCache가 배치될 Private Subnet
variable "subnet_ids" {
  type = list(string)
}

# Serverless Cache 최대 저장 용량(GB)
variable "max_data_storage" {
  type = number
}

# Serverless Cache 최대 처리량(ECPU/sec)
variable "max_ecpu_per_second" {
  type = number
}

# cache Security Group 을 만들 VPC
variable "vpc_id" {
  type = string
}

# Serverless Valkey 6379-6380 인바운드를 허용할 프라이빗 서브넷 CIDR
variable "private_subnet_cidrs" {
  type = list(string)
}

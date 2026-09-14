variable "project_name" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "engine_version" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "max_allocated_storage" {
  type = number
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "backup_retention_period" {
  type = number
}

variable "monitoring_interval" {
  type = number
}

variable "performance_insights_retention_period" {
  type = number
}

variable "enhanced_monitoring_log_retention_days" {
  type = number
}

# RDSOSMetrics 로그 그룹은 RDS 향상된 모니터링이 쓰는 계정·리전 공용 고정 이름이다.
# 이미 다른 스택이 만들어 둔 경우 false 로 두어 생성을 건너뛴다.
variable "create_os_metrics_log_group" {
  description = "RDSOSMetrics CloudWatch 로그 그룹을 이 스택이 생성할지 여부"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "db Security Group 을 만들 VPC"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "5432 인바운드를 허용할 프라이빗 서브넷 CIDR"
  type        = list(string)
}

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

variable "db_security_group_id" {
  type = string
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

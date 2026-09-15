variable "project_name" {
  type = string
}

variable "gcp_project_id" {
  description = "Workload Identity 풀 이름에 들어간다"
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

# GKE 마스터 전용 대역. VPC 의 어떤 서브넷과도 겹치면 안 되고 /28 이어야 한다.
variable "master_cidr" {
  type    = string
  default = "10.10.255.0/28"
}

variable "master_authorized_cidrs" {
  description = "마스터에 접근 가능한 대역 목록"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "disk_size_gb" {
  type    = number
  default = 50
}

# Pilot Light. 평상시 최소로 두고 페일오버 때 올린다.
variable "node_count_min" {
  type    = number
  default = 1
}

variable "node_count_max" {
  type    = number
  default = 4
}

variable "node_service_account_email" {
  type = string
}

variable "deletion_protection" {
  type    = bool
  default = false
}

# =========================================================
# 공통·Provider 설정
# =========================================================

variable "project_name" {
  description = "VPN 리소스 이름 접두사"
  type        = string
}

variable "aws_region" {
  description = "AWS provider 리전"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "default_tags" {
  description = "AWS provider가 모든 지원 리소스에 추가할 기본 태그"
  type        = map(string)
}

# =========================================================
# Remote state 조회 설정
# backend.tf 자체는 Terraform 제약상 input variable을 사용할 수 없다.
# 아래 값은 data.terraform_remote_state 조회에만 사용한다.
# =========================================================

variable "remote_state_bucket" {
  description = "core 및 Cloud SQL remote state가 저장된 S3 버킷"
  type        = string
}

variable "remote_state_region" {
  description = "remote state S3 버킷 리전"
  type        = string
}

variable "aws_core_state_key" {
  description = "aws-core state key"
  type        = string
}

variable "gcp_core_state_key" {
  description = "gcp-core state key"
  type        = string
}

variable "gcp_cloudsql_state_key" {
  description = "gcp-cloudsql state key"
  type        = string
}

# =========================================================
# AWS data source 조회 조건
# ID 자체는 tfvars에 기록하지 않고 아래 이름으로 현재 값을 조회한다.
# =========================================================

variable "aws_private_route_table_name_patterns" {
  description = "VGW 경로 전파 대상 private route table Name 패턴"
  type        = list(string)
}

variable "aws_public_route_table_names" {
  description = "VGW 경로 전파 대상 public route table Name"
  type        = list(string)
}

# =========================================================
# BGP·VPN 설정
# =========================================================

variable "aws_asn" {
  description = "AWS VGW BGP ASN"
  type        = number
}

variable "gcp_asn" {
  description = "GCP Cloud Router BGP ASN. gcp-core의 ASN과 같아야 함"
  type        = number
}

variable "gcp_advertised_groups" {
  description = "각 BGP 세션에서 함께 광고할 GCP 경로 그룹"
  type        = list(string)
}

variable "gcp_additional_advertised_ip_ranges" {
  description = "data source에서 가져오는 Cloud SQL /32 외에 추가로 광고할 IPv4 CIDR 목록"
  type = list(object({
    range       = string
    description = string
  }))

  validation {
    condition = alltrue([
      for item in var.gcp_additional_advertised_ip_ranges : can(cidrnetmask(item.range))
    ])
    error_message = "추가 광고 range는 유효한 IPv4 CIDR이어야 합니다."
  }
}

variable "advertised_route_priority" {
  description = "GCP BGP advertised route priority(MED)"
  type        = number

  validation {
    condition     = var.advertised_route_priority >= 0 && var.advertised_route_priority <= 65535
    error_message = "advertised_route_priority는 0~65535 사이여야 합니다."
  }
}

variable "ike_version" {
  description = "GCP VPN 터널 IKE 버전"
  type        = number

  validation {
    condition     = contains([1, 2], var.ike_version)
    error_message = "ike_version은 1 또는 2여야 합니다."
  }
}

variable "tunnel_inside_cidrs" {
  description = "AWS VPN 연결별 터널 내부 /30 CIDR 2개씩"
  type        = map(list(string))

  validation {
    condition = (
      toset(keys(var.tunnel_inside_cidrs)) == toset(["0", "1"]) &&
      alltrue([for cidrs in values(var.tunnel_inside_cidrs) : length(cidrs) == 2]) &&
      alltrue([for cidr in flatten(values(var.tunnel_inside_cidrs)) : can(cidrnetmask(cidr))])
    )
    error_message = "tunnel_inside_cidrs는 키 0·1마다 유효한 /30 CIDR 두 개를 가져야 합니다."
  }
}

# 터널 4개의 사전 공유 키. 실제 값은 gitignore된 terraform.tfvars에만 기록한다.
variable "tunnel_preshared_keys" {
  description = "VPN 연결별 터널 사전 공유 키 2개씩"
  type        = map(list(string))
  sensitive   = true

  validation {
    condition = (
      toset(keys(var.tunnel_preshared_keys)) == toset(["0", "1"]) &&
      alltrue([for keys in values(var.tunnel_preshared_keys) : length(keys) == 2]) &&
      alltrue([
        for key in flatten(values(var.tunnel_preshared_keys)) :
        length(key) >= 8 && length(key) <= 64 && !startswith(key, "0") && !startswith(key, "REPLACE_ME")
      ])
    )
    error_message = "각 PSK는 8~64자이고 0으로 시작할 수 없습니다. REPLACE_ME 값을 실제 기존 PSK로 교체하세요."
  }
}

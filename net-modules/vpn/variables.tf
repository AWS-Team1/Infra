variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

# ---------- AWS ----------

variable "aws_vpc_id" {
  type = string
}

# BGP 로 배운 GCP 대역을 전파할 라우트 테이블.
# DMS용 프라이빗 라우트 테이블과 bastion용 퍼블릭 라우트 테이블을 넣는다.
variable "aws_route_table_ids" {
  description = "경로 전파를 켤 AWS 라우트 테이블 ID 목록"
  type        = list(string)
}

variable "aws_asn" {
  description = "AWS VGW 의 BGP ASN. GCP Cloud Router ASN 과 달라야 한다"
  type        = number
}

# ---------- GCP ----------

variable "gcp_network_id" {
  type = string
}

variable "gcp_region" {
  type = string
}

# gcp-core 가 만든 Cloud Router 를 재사용한다(NAT 와 공용).
variable "gcp_router_name" {
  type = string
}

variable "gcp_asn" {
  description = "GCP Cloud Router 의 BGP ASN. gcp-core 의 cloud_router_asn 과 같아야 한다"
  type        = number
}

variable "gcp_advertised_groups" {
  description = "CUSTOM BGP 광고에 포함할 경로 그룹"
  type        = list(string)
}

variable "gcp_advertised_ip_ranges" {
  description = "모든 BGP 피어에서 GCP 서브넷과 함께 광고할 추가 IPv4 CIDR 목록(예: Cloud SQL PSA /32)"
  type = list(object({
    range       = string
    description = string
  }))

  validation {
    condition = alltrue([
      for item in var.gcp_advertised_ip_ranges : can(cidrnetmask(item.range))
    ])
    error_message = "gcp_advertised_ip_ranges의 range는 유효한 IPv4 CIDR이어야 합니다."
  }
}

# ---------- 터널 ----------

# AWS 가 무작위로 배정하게 두면 GCP 쪽 설정이 매 apply 마다 흔들린다.
# 169.254.0.0/16 중 /30 을 직접 지정한다. AWS 예약 대역을 피해야 한다.
variable "tunnel_inside_cidrs" {
  description = "VPN 연결별 터널 내부 /30 CIDR 2개씩"
  type        = map(list(string))
}

variable "ike_version" {
  description = "GCP VPN 터널 IKE 버전"
  type        = number
}

variable "advertised_route_priority" {
  description = "GCP BGP advertised route priority(MED)"
  type        = number
}

# 사전 공유 키. terraform.tfvars 로 넘기고 저장소에 커밋하지 않는다.
# 길이 8~64, 0 으로 시작할 수 없다.
variable "tunnel_preshared_keys" {
  description = "VPN 연결별 터널 사전 공유 키 2개씩"
  type        = map(list(string))
  sensitive   = true
}

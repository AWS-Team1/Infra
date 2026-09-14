variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

# ---------- AWS ----------

variable "aws_vpc_id" {
  type = string
}

# BGP 로 배운 GCP 대역을 전파할 라우트 테이블.
# 프라이빗 라우트 테이블을 넣는다 — DMS 복제 인스턴스가 거기 있다.
variable "aws_route_table_ids" {
  description = "경로 전파를 켤 AWS 라우트 테이블 ID 목록"
  type        = list(string)
}

variable "aws_asn" {
  description = "AWS VGW 의 BGP ASN. GCP Cloud Router ASN 과 달라야 한다"
  type        = number
  default     = 64512
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
  default     = 64514
}

# ---------- 터널 ----------

# AWS 가 무작위로 배정하게 두면 GCP 쪽 설정이 매 apply 마다 흔들린다.
# 169.254.0.0/16 중 /30 을 직접 지정한다. AWS 예약 대역을 피해야 한다.
variable "tunnel_inside_cidrs" {
  description = "VPN 연결별 터널 내부 /30 CIDR 2개씩"
  type        = map(list(string))

  default = {
    "0" = ["169.254.10.0/30", "169.254.10.4/30"]
    "1" = ["169.254.10.8/30", "169.254.10.12/30"]
  }
}

# 사전 공유 키. terraform.tfvars 로 넘기고 저장소에 커밋하지 않는다.
# 길이 8~64, 0 으로 시작할 수 없다.
variable "tunnel_preshared_keys" {
  description = "VPN 연결별 터널 사전 공유 키 2개씩"
  type        = map(list(string))
  sensitive   = true
}

# =========================================================
# gcp-core — GCP 쪽 네트워크 기반
# AWS 의 aws-core 와 같은 자리다. 다른 GCP 루트는 이 루트만 참조한다(1단 평면).
#
# ⚠️ CIDR 설계 — AWS VPC 가 192.168.0.0/16 이다.
#    GCP 는 10.10.0.0/16 대역을 쓴다. VPN 으로 이을 것이므로 겹치면 안 된다.
# =========================================================

module "network" {
  source = "../gcp-modules/network"

  project_name = "boa"
  region       = var.region

  subnet_cidr   = "10.10.0.0/20"  # GKE 노드
  pods_cidr     = "10.10.16.0/20" # 파드 별칭 IP
  services_cidr = "10.10.32.0/20" # 서비스 별칭 IP

  # VPN 너머 AWS 대역. 방화벽 source_ranges 로 들어간다.
  # aws-core 의 VPC CIDR 과 일치해야 한다.
  aws_vpc_cidrs = ["192.168.0.0/16"]

  # HA VPN 의 BGP 에서 재사용한다. AWS 쪽 ASN(64512)과 달라야 한다.
  cloud_router_asn = 64514
}

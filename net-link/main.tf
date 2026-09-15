# =========================================================
# net-link — AWS ↔ GCP 크로스클라우드 VPN
#
# 이 저장소에서 유일하게 두 클라우드를 동시에 참조하는 루트다.
# 지금까지 모든 루트는 자기 클라우드의 core 하나만 봤다(1단 평면).
# VPN 은 본질적으로 양쪽을 잇는 것이라 그 원칙이 여기서만 깨진다.
#
# DMS 보다 수명이 길다. DR 리허설마다 aws-dms 를 destroy 해도
# 이 루트는 그대로 둔다 — 터널 재수립이 느리기 때문이다.
# =========================================================

data "terraform_remote_state" "aws_core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "gcp_core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "gcp/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# BGP 가 배운 GCP 대역을 프라이빗 라우트 테이블에 전파해야 한다.
# aws-core 는 라우트 테이블 ID 를 출력하지 않으므로 태그로 조회한다.
# (aws-core 의 output 계약을 건드리지 않으려는 선택이다)
data "aws_route_tables" "private" {
  vpc_id = data.terraform_remote_state.aws_core.outputs.vpc_id

  filter {
    name   = "tag:Name"
    values = ["boa-private-rt-*"]
  }
}

module "vpn" {
  source = "../net-modules/vpn"

  project_name = "boa"

  # ---- AWS ----
  aws_vpc_id          = data.terraform_remote_state.aws_core.outputs.vpc_id
  aws_route_table_ids = data.aws_route_tables.private.ids
  aws_asn             = 64512

  # ---- GCP ----
  gcp_network_id  = data.terraform_remote_state.gcp_core.outputs.network_id
  gcp_region      = data.terraform_remote_state.gcp_core.outputs.region
  gcp_router_name = data.terraform_remote_state.gcp_core.outputs.router_name

  # gcp-core 의 cloud_router_asn 과 반드시 같아야 한다.
  gcp_asn = 64514

  # 사전 공유 키는 terraform.tfvars 로 넘긴다. 저장소에 커밋하지 않는다.
  tunnel_preshared_keys = var.tunnel_preshared_keys
}

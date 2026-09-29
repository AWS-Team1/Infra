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
    bucket = var.remote_state_bucket
    key    = var.aws_core_state_key
    region = var.remote_state_region
  }
}

data "terraform_remote_state" "gcp_core" {
  backend = "s3"

  config = {
    bucket = var.remote_state_bucket
    key    = var.gcp_core_state_key
    region = var.remote_state_region
  }
}

# Cloud SQL 비공개 IP를 BGP 커스텀 경로로 광고한다.
# IP를 코드에 고정하지 않아 인스턴스를 재생성해 주소가 바뀌어도
# gcp-cloudsql 적용 후 net-link를 다시 적용하면 새 /32 경로로 갱신된다.
data "terraform_remote_state" "gcp_cloudsql" {
  backend = "s3"

  config = {
    bucket = var.remote_state_bucket
    key    = var.gcp_cloudsql_state_key
    region = var.remote_state_region
  }
}

locals {
  # 환경에서 파생되는 ID·IP는 tfvars에 복제하지 않고 state/data 조회값을 단일 출처로 쓴다.
  aws_vpc_id              = data.terraform_remote_state.aws_core.outputs.vpc_id
  gcp_network_id          = data.terraform_remote_state.gcp_core.outputs.network_id
  gcp_region              = data.terraform_remote_state.gcp_core.outputs.region
  gcp_router_name         = data.terraform_remote_state.gcp_core.outputs.router_name
  gcp_cloudsql_private_ip = data.terraform_remote_state.gcp_cloudsql.outputs.private_ip_address
  gcp_advertised_ip_ranges = concat(
    [{
      range       = "${local.gcp_cloudsql_private_ip}/32"
      description = "Cloud SQL private IP through PSA"
    }],
    var.gcp_additional_advertised_ip_ranges,
  )
}

# BGP 가 배운 GCP 대역을 DMS용 프라이빗 라우트 테이블과
# 점프 호스트용 퍼블릭 라우트 테이블에 전파해야 한다.
# aws-core 는 라우트 테이블 ID 를 출력하지 않으므로 태그로 조회한다.
# (aws-core 의 output 계약을 건드리지 않으려는 선택이다)
data "aws_route_tables" "private" {
  vpc_id = local.aws_vpc_id

  filter {
    name   = "tag:Name"
    values = var.aws_private_route_table_name_patterns
  }
}

data "aws_route_tables" "public" {
  vpc_id = local.aws_vpc_id

  filter {
    name   = "tag:Name"
    values = var.aws_public_route_table_names
  }
}

locals {
  aws_route_table_ids = sort(distinct(concat(
    data.aws_route_tables.private.ids,
    data.aws_route_tables.public.ids,
  )))
}

module "vpn" {
  source = "../net-modules/vpn"

  project_name = var.project_name

  # ---- AWS ----
  aws_vpc_id          = local.aws_vpc_id
  aws_route_table_ids = local.aws_route_table_ids
  aws_asn             = var.aws_asn

  # ---- GCP ----
  gcp_network_id  = local.gcp_network_id
  gcp_region      = local.gcp_region
  gcp_router_name = local.gcp_router_name

  # gcp-core 의 cloud_router_asn 과 반드시 같아야 한다.
  gcp_asn = var.gcp_asn

  # PSA 주소는 일반 VPC 서브넷이 아니므로 ALL_SUBNETS 광고에 포함되지 않는다.
  # Cloud SQL의 현재 비공개 IP만 /32로 네 BGP 세션에 추가 광고한다.
  gcp_advertised_groups     = var.gcp_advertised_groups
  gcp_advertised_ip_ranges  = local.gcp_advertised_ip_ranges
  advertised_route_priority = var.advertised_route_priority
  ike_version               = var.ike_version
  tunnel_inside_cidrs       = var.tunnel_inside_cidrs

  # 사전 공유 키는 terraform.tfvars 로 넘긴다. 저장소에 커밋하지 않는다.
  tunnel_preshared_keys = var.tunnel_preshared_keys
}

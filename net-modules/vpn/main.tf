# =========================================================
# AWS ↔ GCP Site-to-Site VPN (HA, BGP)
#
# 이 모듈만 유일하게 두 프로바이더를 동시에 쓴다. 양쪽 자원이 서로의 IP 를
# 참조해야 해서 한 그래프 안에 있어야 순서가 풀리기 때문이다.
#
#   GCP HA VPN 게이트웨이 생성 (외부 IP 2개 할당)
#        ↓  그 IP 를 고객 게이트웨이로
#   AWS Customer Gateway ×2  →  AWS VPN Connection ×2 (각 2터널 = 총 4터널)
#        ↓  AWS 터널 외부 IP 4개를
#   GCP External VPN Gateway (FOUR_IPS)  →  VPN Tunnel ×4  →  BGP 피어 ×4
#
# 터널이 4개인 이유는 HA 다. GCP 인터페이스 2개 × AWS 터널 2개.
# 이 구조가 GCP 가 권장하는 99.99% 가용성 배치다.
#
# ⚠️ 사전 확인 — AWS 192.168.0.0/16 과 GCP 10.10.0.0/16 이 겹치지 않아야 한다.
# =========================================================

# ---------------------------------------------------------
# 1. GCP HA VPN 게이트웨이 — 먼저 만들어야 외부 IP 가 생긴다
# ---------------------------------------------------------
resource "google_compute_ha_vpn_gateway" "main" {

  name    = "${var.project_name}-ha-vpn"
  region  = var.gcp_region
  network = var.gcp_network_id
}


# ---------------------------------------------------------
# 2. AWS 쪽 — VGW 와 고객 게이트웨이
# ---------------------------------------------------------

resource "aws_vpn_gateway" "main" {

  vpc_id          = var.aws_vpc_id
  amazon_side_asn = var.aws_asn

  tags = {
    Name = "${var.project_name}-vgw"
  }
}

# 프라이빗 라우트 테이블이 BGP 로 배운 GCP 대역을 자동으로 받게 한다.
# 이게 없으면 DMS 복제 인스턴스가 Cloud SQL 로 가는 경로를 모른다.
resource "aws_vpn_gateway_route_propagation" "private" {

  for_each = toset(var.aws_route_table_ids)

  vpn_gateway_id = aws_vpn_gateway.main.id
  route_table_id = each.value
}

# GCP HA VPN 의 인터페이스 2개를 각각 고객 게이트웨이로 등록한다.
resource "aws_customer_gateway" "gcp" {

  for_each = { for i in [0, 1] : tostring(i) => i }

  bgp_asn    = var.gcp_asn
  ip_address = google_compute_ha_vpn_gateway.main.vpn_interfaces[each.value].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "${var.project_name}-cgw-gcp-if${each.key}"
  }
}

# VPN 연결 2개. 각각 터널 2개를 갖는다.
# 터널 내부 CIDR 과 사전 공유 키를 명시해 GCP 쪽에서 같은 값을 그대로 쓴다.
# (명시하지 않으면 AWS 가 무작위로 만들고, GCP 쪽 설정이 복잡해진다)
resource "aws_vpn_connection" "gcp" {

  for_each = aws_customer_gateway.gcp

  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = each.value.id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_inside_cidr   = var.tunnel_inside_cidrs[each.key][0]
  tunnel2_inside_cidr   = var.tunnel_inside_cidrs[each.key][1]
  tunnel1_preshared_key = var.tunnel_preshared_keys[each.key][0]
  tunnel2_preshared_key = var.tunnel_preshared_keys[each.key][1]

  tags = {
    Name = "${var.project_name}-vpn-if${each.key}"
  }
}


# ---------------------------------------------------------
# 3. GCP 쪽 — AWS 를 외부 게이트웨이로 등록하고 터널 4개를 건다
# ---------------------------------------------------------

locals {
  # AWS 터널 외부 IP 4개를 GCP 외부 게이트웨이 인터페이스 0~3 에 매핑한다.
  # 순서가 중요하다. 아래 tunnels 맵이 이 인덱스를 그대로 참조한다.
  aws_tunnel_ips = [
    aws_vpn_connection.gcp["0"].tunnel1_address,
    aws_vpn_connection.gcp["0"].tunnel2_address,
    aws_vpn_connection.gcp["1"].tunnel1_address,
    aws_vpn_connection.gcp["1"].tunnel2_address,
  ]

  # GCP 터널 4개의 정의.
  #  gcp_if  : HA VPN 게이트웨이의 인터페이스 번호 (0 또는 1)
  #  peer_if : 위 aws_tunnel_ips 의 인덱스
  #  conn/tun: BGP 주소와 PSK 를 꺼내올 AWS 연결·터널 번호
  tunnels = {
    "0" = { gcp_if = 0, peer_if = 0, conn = "0", tun = 1 }
    "1" = { gcp_if = 0, peer_if = 1, conn = "0", tun = 2 }
    "2" = { gcp_if = 1, peer_if = 2, conn = "1", tun = 1 }
    "3" = { gcp_if = 1, peer_if = 3, conn = "1", tun = 2 }
  }

  # AWS 가 알려주는 터널 내부 주소. GCP 라우터 인터페이스와 BGP 피어에 쓴다.
  #  cgw_inside = GCP 쪽 주소, vgw_inside = AWS 쪽 주소
  tunnel_addrs = {
    for k, t in local.tunnels : k => {
      cgw_inside = t.tun == 1 ? aws_vpn_connection.gcp[t.conn].tunnel1_cgw_inside_address : aws_vpn_connection.gcp[t.conn].tunnel2_cgw_inside_address
      vgw_inside = t.tun == 1 ? aws_vpn_connection.gcp[t.conn].tunnel1_vgw_inside_address : aws_vpn_connection.gcp[t.conn].tunnel2_vgw_inside_address
      psk        = t.tun == 1 ? aws_vpn_connection.gcp[t.conn].tunnel1_preshared_key : aws_vpn_connection.gcp[t.conn].tunnel2_preshared_key
    }
  }
}

resource "google_compute_external_vpn_gateway" "aws" {

  name            = "${var.project_name}-aws-gw"
  redundancy_type = "FOUR_IPS_REDUNDANCY"
  description     = "AWS Site-to-Site VPN tunnel endpoints"

  dynamic "interface" {
    for_each = local.aws_tunnel_ips

    content {
      id         = interface.key
      ip_address = interface.value
    }
  }
}

resource "google_compute_vpn_tunnel" "main" {

  for_each = local.tunnels

  name   = "${var.project_name}-tunnel-${each.key}"
  region = var.gcp_region
  router = var.gcp_router_name

  vpn_gateway                     = google_compute_ha_vpn_gateway.main.id
  vpn_gateway_interface           = each.value.gcp_if
  peer_external_gateway           = google_compute_external_vpn_gateway.aws.id
  peer_external_gateway_interface = each.value.peer_if

  shared_secret = local.tunnel_addrs[each.key].psk
  ike_version   = 2
}

# BGP 세션. AWS 가 배정한 터널 내부 /30 을 그대로 쓴다.
resource "google_compute_router_interface" "main" {

  for_each = local.tunnels

  name       = "${var.project_name}-if-${each.key}"
  region     = var.gcp_region
  router     = var.gcp_router_name
  ip_range   = "${local.tunnel_addrs[each.key].cgw_inside}/30"
  vpn_tunnel = google_compute_vpn_tunnel.main[each.key].name
}

resource "google_compute_router_peer" "main" {

  for_each = local.tunnels

  name            = "${var.project_name}-peer-${each.key}"
  region          = var.gcp_region
  router          = var.gcp_router_name
  interface       = google_compute_router_interface.main[each.key].name
  peer_ip_address = local.tunnel_addrs[each.key].vgw_inside
  peer_asn        = var.aws_asn

  advertised_route_priority = 100
}

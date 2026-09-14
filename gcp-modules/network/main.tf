# =========================================================
# GCP Network
# AWS 의 aws-modules/network 와 같은 역할이다. 차이는 두 가지다.
#  1. GCP 서브넷은 리전 단위다. AZ(=zone)별로 쪼개지 않는다
#  2. Cloud SQL 프라이빗 IP 를 쓰려면 private services access(PSA)가 필요하다.
#     Google 이 관리하는 VPC 와 내 VPC 를 피어링하는 구조다
# =========================================================

resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"

  description = "BoA DR standby network"
}


# GKE 노드가 들어갈 서브넷.
# 파드·서비스는 별칭 IP 범위(secondary range)를 쓴다. 노드 대역과 겹치지 않는다.
resource "google_compute_subnetwork" "main" {
  name          = "${var.project_name}-subnet"
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = var.subnet_cidr

  # 프라이빗 노드가 Google API 로 나갈 때 쓴다.
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.project_name}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.project_name}-services"
    ip_cidr_range = var.services_cidr
  }
}


# =========================================================
# Private Services Access (Cloud SQL 프라이빗 IP 의 전제)
# Cloud SQL 인스턴스는 내 VPC 가 아니라 Google 관리 VPC 에 생기고,
# 아래 피어링을 통해 내 VPC 에서 사설 IP 로 보인다.
#
# ⚠️ 이 피어링은 전이(transitive)되지 않는다.
#    VPN 건너편(AWS) 에서 Cloud SQL 로 직접 가려면 export_custom_routes 가 필요하다.
#    AWS DMS 경로에서는 DMS 가 AWS 쪽에서 Cloud SQL 로 접속하므로 이 설정이 필수다.
# =========================================================

resource "google_compute_global_address" "psa" {
  name          = "${var.project_name}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}

# 피어링에 커스텀 경로 내보내기를 켠다.
# 이게 없으면 Cloud SQL 은 VPN 너머 AWS 대역으로 가는 경로를 배우지 못한다.
resource "google_compute_network_peering_routes_config" "psa" {
  peering = google_service_networking_connection.psa.peering
  network = google_compute_network.main.name

  import_custom_routes = true
  export_custom_routes = true
}


# =========================================================
# Cloud Router + NAT
# 프라이빗 노드가 외부(이미지 풀 등)로 나가는 경로. AWS 의 NAT 게이트웨이에 해당한다.
# Cloud Router 는 뒤에서 HA VPN 의 BGP 세션에도 재사용한다.
# =========================================================

resource "google_compute_router" "main" {
  name    = "${var.project_name}-router"
  region  = var.region
  network = google_compute_network.main.id

  bgp {
    asn = var.cloud_router_asn
  }
}

resource "google_compute_router_nat" "main" {
  name                               = "${var.project_name}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}


# =========================================================
# Firewall
# GCP 는 기본이 전부 차단이라 명시적으로 열어야 한다.
# AWS 쪽에서 오는 트래픽(VPN 경유)을 CIDR 로 연다 — aws-modules/rds 가
# 서브넷 CIDR 로 여는 것과 같은 방식이다.
# =========================================================

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.project_name}-allow-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
  description   = "VPC 내부 통신"
}

# AWS 대역에서 오는 접속. VPN 이 서기 전에는 이 규칙이 있어도 트래픽이 없다.
resource "google_compute_firewall" "allow_from_aws" {
  name    = "${var.project_name}-allow-from-aws"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["5432", "443", "22"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = var.aws_vpc_cidrs
  description   = "VPN 경유 AWS 대역 (DMS · 운영 접근)"
}

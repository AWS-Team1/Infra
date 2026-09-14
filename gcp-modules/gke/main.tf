# =========================================================
# GKE — DR 대기 클러스터 (Pilot Light)
#
# AWS EKS 와 역할이 대칭이지만 규모가 다르다. 평상시에는 최소 노드만 돌고,
# 페일오버 시 노드 수와 앱 replicas 를 올린다.
#
# EKS 와 달리 GKE 는 로드밸런서 컨트롤러와 CSI 드라이버가 내장이라
# 따로 설치할 애드온이 적다.
# =========================================================

resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.region

  # 기본 노드 풀을 만들고 바로 지운다. 노드 풀을 따로 관리하기 위한 관용 패턴이다.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_id
  subnetwork = var.subnet_id

  # 파드·서비스에 별칭 IP 를 준다. AWS VPC CNI 가 파드에 VPC IP 를 주는 것과 같은 개념이다.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # 노드에 공인 IP 를 주지 않는다. 외부로는 Cloud NAT 로 나간다.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # 콘솔·CI 에서 접근해야 하므로 공개 엔드포인트는 남긴다
    master_ipv4_cidr_block  = var.master_cidr
  }

  # 마스터에 접근할 수 있는 대역을 좁힌다.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs

      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Workload Identity — AWS 의 IRSA 에 해당한다.
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # 대기 클러스터를 실수로 지우지 않게 한다.
  deletion_protection = var.deletion_protection

  lifecycle {
    ignore_changes = [
      # 기본 노드 풀 제거 후 초기값이 되돌아오는 것을 무시한다.
      initial_node_count,
    ]
  }
}


# Pilot Light 노드 풀. 평상시 최소, 페일오버 시 스케일업한다.
resource "google_container_node_pool" "main" {
  name     = "${var.cluster_name}-np"
  location = var.region
  cluster  = google_container_cluster.main.name

  initial_node_count = var.node_count_min

  autoscaling {
    min_node_count = var.node_count_min
    max_node_count = var.node_count_max
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-balanced"

    # 노드는 전용 서비스 계정을 쓴다. 기본 컴퓨트 SA 는 권한이 과하다.
    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      role = "dr-standby"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

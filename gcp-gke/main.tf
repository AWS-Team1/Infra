# =========================================================
# gcp-gke — DR 대기 클러스터
# gcp-core 만 참조한다. gcp-cloudsql 을 알지 못한다(1단 평면).
#
# 평상시 노드 1대로 떠 있고 앱 replicas 는 0 이다(Pilot Light).
# 페일오버 시 replicas 를 올리면 오토스케일러가 노드를 늘린다.
# =========================================================

data "terraform_remote_state" "gcp_core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "gcp/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# 노드 전용 서비스 계정. 기본 컴퓨트 SA 는 프로젝트 편집자 권한이라 쓰지 않는다.
resource "google_service_account" "gke_node" {
  account_id   = "boa-gke-node"
  display_name = "BoA GKE node service account"
}

# 노드가 로그·지표를 보내고 Artifact Registry 에서 이미지를 받는 데 필요한 최소 역할.
resource "google_project_iam_member" "gke_node" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

module "gke" {
  source = "../gcp-modules/gke"

  project_name   = "boa"
  gcp_project_id = var.gcp_project_id
  cluster_name   = "boa-gke"
  region         = var.region

  network_id          = data.terraform_remote_state.gcp_core.outputs.network_id
  subnet_id           = data.terraform_remote_state.gcp_core.outputs.subnet_id
  pods_range_name     = data.terraform_remote_state.gcp_core.outputs.pods_range_name
  services_range_name = data.terraform_remote_state.gcp_core.outputs.services_range_name

  # VPC 의 어떤 서브넷과도 겹치지 않아야 한다. 10.10.0/16/32 대역을 피해 255 로 둔다.
  master_cidr             = "10.10.255.0/28"
  master_authorized_cidrs = concat(var.master_authorized_cidrs, var.runner_authorized_cidrs)

  machine_type   = "e2-standard-2"
  node_count_min = 3
  node_count_max = 4

  node_service_account_email = google_service_account.gke_node.email

  deletion_protection = false
}

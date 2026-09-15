# 다른 GCP 루트가 terraform_remote_state 로 읽는 계약이다.
# 이름을 바꾸면 소비 루트가 깨진다. (aws-core/outputs.tf 와 같은 규칙)

output "network_id" {
  value = google_compute_network.main.id
}

output "network_name" {
  value = google_compute_network.main.name
}

output "network_self_link" {
  value = google_compute_network.main.self_link
}

output "subnet_id" {
  value = google_compute_subnetwork.main.id
}

output "subnet_name" {
  value = google_compute_subnetwork.main.name
}

output "pods_range_name" {
  value = "${var.project_name}-pods"
}

output "services_range_name" {
  value = "${var.project_name}-services"
}

# gcp-cloudsql 이 private_network 로 쓴다. PSA 연결이 선행돼야 하므로
# 이 출력을 참조하는 것 자체가 순서를 보장한다.
output "psa_connection" {
  value = google_service_networking_connection.psa.id
}

# net-link(VPN)가 BGP 세션을 붙일 때 재사용한다.
output "router_name" {
  value = google_compute_router.main.name
}

output "region" {
  value = var.region
}

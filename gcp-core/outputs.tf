# 다른 GCP 루트가 terraform_remote_state 로 읽는 계약이다.
# 이름을 바꾸면 소비 루트가 깨진다. (aws-core/outputs.tf 와 같은 규칙)

output "network_id" {
  value = module.network.network_id
}

output "network_name" {
  value = module.network.network_name
}

output "network_self_link" {
  value = module.network.network_self_link
}

output "subnet_id" {
  value = module.network.subnet_id
}

output "pods_range_name" {
  value = module.network.pods_range_name
}

output "services_range_name" {
  value = module.network.services_range_name
}

# gcp-cloudsql 이 사설 IP 할당 전제로 읽는다.
output "psa_connection" {
  value = module.network.psa_connection
}

# net-link(VPN)가 BGP 세션을 붙일 때 읽는다.
output "router_name" {
  value = module.network.router_name
}

output "region" {
  value = module.network.region
}

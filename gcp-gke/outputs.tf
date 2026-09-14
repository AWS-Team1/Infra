output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_endpoint" {
  value = module.gke.cluster_endpoint
}

output "node_service_account_email" {
  value = google_service_account.gke_node.email
}

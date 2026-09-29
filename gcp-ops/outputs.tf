output "argocd_global_ip" {
  value = google_compute_global_address.argocd.address
}

output "argocd_url" {
  value = "https://${trimsuffix(google_dns_record_set.argocd.name, ".")}"
}

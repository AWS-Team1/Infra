output "argocd_global_ip" {
  value = google_compute_global_address.argocd.address
}

output "argocd_url" {
  value = "https://${aws_route53_record.argocd.fqdn}"
}

output "dashboard_id" {
  description = "Cloud Monitoring dashboard resource ID"
  value       = google_monitoring_dashboard.infrastructure.id
}

output "dashboard_url" {
  description = "GCP 콘솔에서 dashboard를 여는 URL"
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${basename(google_monitoring_dashboard.infrastructure.id)}?project=${var.gcp_project_id}"
}

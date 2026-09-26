output "bucket_name" {
  description = "GCS bucket that stores cross-cloud copies of AWS Terraform state backups."
  value       = google_storage_bucket.terraform_state_backup.name
}

output "bucket_location" {
  description = "GCS location of the cross-cloud Terraform state backup bucket."
  value       = google_storage_bucket.terraform_state_backup.location
}

output "object_prefix" {
  description = "Top-level GCS prefix for immutable Terraform state backup sets."
  value       = local.object_prefix
}

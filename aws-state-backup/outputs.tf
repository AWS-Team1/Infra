output "bucket_name" {
  description = "Tokyo S3 bucket used only for Terraform state DR backup copies."
  value       = aws_s3_bucket.terraform_state_backup.id
}

output "bucket_region" {
  description = "AWS Region of the Terraform state DR backup bucket."
  value       = local.backup_region
}

output "object_prefix" {
  description = "Top-level S3 prefix for immutable Terraform state backup sets."
  value       = local.backup_object_prefix
}

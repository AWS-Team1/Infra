locals {
  bucket_name   = "boa-terraform-state-backup-${var.gcp_project_id}"
  object_prefix = "terraform-state-backups"
}

resource "google_storage_bucket" "terraform_state_backup" {
  name     = local.bucket_name
  project  = var.gcp_project_id
  location = "ASIA-NORTHEAST1"

  storage_class               = "STANDARD"
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Cloud Storage encrypts objects at rest with Google-managed encryption by
  # default. No service-account key or repository-managed key is required.
  lifecycle {
    prevent_destroy = true
  }

  labels = {
    project    = "boa"
    purpose    = "terraform-state-dr-backup"
    managed_by = "terraform"
  }
}

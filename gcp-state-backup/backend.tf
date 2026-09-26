terraform {
  backend "s3" {
    # This root creates the GCS destination; its own state remains in the
    # existing Seoul S3 backend to avoid a circular bootstrap dependency.
    bucket       = "boa-terraform-state-6416"
    key          = "gcp/state-backup/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

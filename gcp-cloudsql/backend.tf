terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "gcp/cloudsql/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    use_lockfile = true
  }
}

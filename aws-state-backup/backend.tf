terraform {
  backend "s3" {
    # The backup bucket is not a Terraform backend. This root keeps using the
    # existing primary backend in Seoul like every other AWS lifecycle root.
    bucket       = "boa-terraform-state-6416"
    key          = "aws/state-backup/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

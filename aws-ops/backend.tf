terraform {
  backend "s3" {
    # Embedded bootstrap values make a fresh Code Server clone work with
    # ordinary terraform init; CI supplies the same env/backend.hcl values.
    bucket       = "boa-terraform-state-6416"
    key          = "aws/ops/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

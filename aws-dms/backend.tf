terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "aws/dms/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    use_lockfile = true
  }
}

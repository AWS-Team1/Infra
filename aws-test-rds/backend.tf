terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "aws/test/rds/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    use_lockfile = true
  }
}

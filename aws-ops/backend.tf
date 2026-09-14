terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "aws/ops/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    # S3 네이티브 락 (Terraform 1.10+). DynamoDB 테이블 불필요.
    use_lockfile = true
  }
}

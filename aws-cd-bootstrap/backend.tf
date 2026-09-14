terraform {
  backend "s3" {
    # HARD-CODED: 다른 계정에서는 state bucket/region/key를 변경한다.
    bucket  = "boa-terraform-state-6416"
    key     = "aws/cd-bootstrap/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    use_lockfile = true
  }
}

terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "gcp/core/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    # AWS 루트와 같은 버킷을 쓴다. state 는 GCP 리소스지만 백엔드는 팀이 이미
    # 운영 중인 S3 하나로 모은다. key 로만 구분한다.
    use_lockfile = true
  }
}

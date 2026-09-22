# 이 모듈만 두 프로바이더를 함께 요구한다.
# 루트(net-link)의 기본 프로바이더를 상속받는다.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.33"
    }
  }
}

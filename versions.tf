terraform {
  required_version = ">= 1.10.0"

  # AWS 리소스 생성을 위한 Provider
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Valkey 인증용 랜덤 비밀번호 생성
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }


  }
}

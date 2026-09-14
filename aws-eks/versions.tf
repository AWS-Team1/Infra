terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # ALB 컨트롤러(helm)와 secrets-store RBAC 때문에 필요하다.
    # 이 둘을 클러스터 밖으로 빼면 aws 하나로 줄어든다 (개선 과제).
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

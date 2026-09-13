provider "aws" {
  region = "ap-northeast-2"

  # 태그 가능한 모든 리소스에 자동으로 붙는다.
  # Name 은 리소스마다 달라야 하므로 여기 두지 않는다.
  default_tags {
    tags = {
      Project   = "boa"
      Component = "eks"
      ManagedBy = "terraform"
      Repo      = "swoobuntu/Infra"
    }
  }
}

provider "kubernetes" {
  host = module.eks.cluster_endpoint

  cluster_ca_certificate = base64decode(
    module.eks.cluster_certificate_authority_data
  )

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"

    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      "ap-northeast-2"
    ]
  }
}

provider "helm" {
  kubernetes = {
    host = module.eks.cluster_endpoint

    cluster_ca_certificate = base64decode(
      module.eks.cluster_certificate_authority_data
    )

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"

      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        "ap-northeast-2"
      ]
    }
  }
}

provider "aws" {
  region = module.environment.aws_region

  # 태그 가능한 모든 리소스에 자동으로 붙는다.
  # Name 은 리소스마다 달라야 하므로 여기 두지 않는다.
  default_tags {
    tags = {
      Project   = module.environment.project_name
      Component = "eks"
      ManagedBy = "terraform"
      Repo      = "AWS-TEAM1-DEV/Infra"
    }
  }
}

# Migration-only provider compatibility for resources left in the pre-split
# aws-eks state. Kubernetes/Helm resource ownership remains in aws-eks-platform.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", module.environment.aws_region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", module.environment.aws_region]
    }
  }
}

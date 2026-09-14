# aws-core 가 만든 VPC·서브넷을 읽는다. aws-eks 는 참조하지 않는다.
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =========================================================
# ElastiCache Serverless Valkey
# - 로그인 Session / Cache 용도
# =========================================================

module "elasticache" {
  source = "../aws-modules/elasticache"

  project_name = "boa"

  # Cache / RBAC User 이름
  cache_name = "boa-valkey"
  user_name  = "boa-app"

  vpc_id               = data.terraform_remote_state.core.outputs.vpc_id
  private_subnet_cidrs = data.terraform_remote_state.core.outputs.private_subnet_cidrs

  # EKS Private Subnet A/C 공유
  subnet_ids = data.terraform_remote_state.core.outputs.private_subnet_ids

  # Phase 1 테스트용 낮은 사용량 상한
  max_data_storage    = 1
  max_ecpu_per_second = 1000
}

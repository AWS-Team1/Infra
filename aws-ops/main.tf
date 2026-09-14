# =========================================================
# ECR
# - 의존하는 루트가 없다. aws-core 없이도 단독으로 apply 된다
# - 리포지터리 이름은 boa-<서비스명> 이다.
#   접두사 없는 기존 6개(frontend, userservice, ...)는 손으로 만든 것이라
#   이 스택이 소유하지 않는다
# =========================================================

module "ecr" {
  source = "../aws-modules/ecr"

  project_name = "boa"
  region       = "ap-northeast-2"

  repository_names = [
    "frontend",
    "userservice",
    "contacts",
    "balancereader",
    "ledgerwriter",
    "transactionhistory"
  ]

  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  keep_image_count     = 10
}


# =========================================================
# ops ALB
# - ArgoCD 를 외부에 노출한다. 나중에 Grafana · Loki · Tempo 도 여기 붙는다
# - 서비스 ALB 와는 별개다. 그쪽은 Ingress 어노테이션으로 컨트롤러가 만든다
# - 대상 등록은 클러스터의 TargetGroupBinding 이 한다. 생성 직후 대상은 0개다
# =========================================================

data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

module "ops_alb" {
  source = "../aws-modules/ops-alb"

  project_name = "boa"

  vpc_id               = data.terraform_remote_state.core.outputs.vpc_id
  public_subnet_ids    = data.terraform_remote_state.core.outputs.public_subnet_ids
  private_subnet_cidrs = data.terraform_remote_state.core.outputs.private_subnet_cidrs

  # ACM 과 DNS 는 Terraform 관리 대상이 아니다. 이미 있는 것을 읽는다.
  certificate_domain = "*.bespinglobal.site"
  hosted_zone_name   = "bespinglobal.site"

  argocd_host        = "argocd.bespinglobal.site"
  argocd_target_port = 8080
}

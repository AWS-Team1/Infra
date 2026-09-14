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

  # ACM 인증서는 이미 발급된 것을 읽어 쓴다.
  certificate_domain = "*.bespinglobal.site"

  # 리스너 규칙의 Host 조건에만 쓴다. 이 이름의 DNS 레코드는 Terraform 이 만들지 않는다
  # — bespinglobal.site 는 app · prod · origin 이 함께 쓰는 공용 호스팅 영역이다.
  argocd_host        = "argocd.bespinglobal.site"
  argocd_target_port = 8080
}

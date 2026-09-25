# =========================================================
# ops ALB
# - ArgoCD 를 외부에 노출한다. 나중에 Grafana · Loki · Tempo 도 여기 붙는다
# - 서비스 ALB 와는 별개다. 그쪽은 Ingress 어노테이션으로 컨트롤러가 만든다
# - 대상 등록은 클러스터의 TargetGroupBinding 이 한다. 생성 직후 대상은 0개다
# =========================================================

data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = module.environment.state_bucket
    key    = "aws/core/terraform.tfstate"
    region = module.environment.aws_region
  }
}

module "ops_alb" {
  source = "../aws-modules/ops-alb"

  project_name = module.environment.project_name

  vpc_id               = data.terraform_remote_state.core.outputs.vpc_id
  public_subnet_ids    = data.terraform_remote_state.core.outputs.public_subnet_ids
  private_subnet_cidrs = data.terraform_remote_state.core.outputs.private_subnet_cidrs

  # ACM 인증서는 이미 발급된 것을 읽어 쓴다.
  certificate_domain = module.environment.certificate_domain

  # argocd_host는 HTTPS 리스너 Host 조건과 Route53 A(alias) 이름에 함께 사용한다.
  argocd_host        = module.environment.argocd_host
  argocd_target_port = 8080
}

data "aws_route53_zone" "public" {
  # HARD-CODED: ACM 인증서와 ops ALB Host 조건에 맞는 Public Hosted Zone이다.
  name         = "${module.environment.public_zone_name}."
  private_zone = false
}

resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = module.environment.argocd_host
  type    = "A"

  alias {
    name                   = module.ops_alb.alb_dns_name
    zone_id                = module.ops_alb.alb_zone_id
    evaluate_target_health = true
  }
}

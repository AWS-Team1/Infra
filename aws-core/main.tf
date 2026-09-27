# =========================================================
# Network
# - boa-vpc 와 IGW 를 Terraform 으로 새로 생성한다.
# - VPC CIDR: 192.168.0.0/16
# =========================================================

module "network" {
  source = "../aws-modules/network"

  project_name = module.environment.project_name
  cluster_name = module.environment.cluster_name

  region   = module.environment.aws_region
  vpc_cidr = "192.168.0.0/16"

  availability_zones = [
    "ap-northeast-2a",
    "ap-northeast-2c"
  ]

  public_subnet_cidrs = [
    "192.168.2.0/24",
    "192.168.3.0/24"
  ]

  private_subnet_cidrs = [
    "192.168.8.0/24",
    "192.168.9.0/24"
  ]

  db_subnet_cidrs = [
    "192.168.16.0/24",
    "192.168.17.0/24"
  ]

  cache_subnet_cidrs = [
    "192.168.24.0/24",
    "192.168.25.0/24"
  ]
}

# 기존 Private Hosted Zone 을 새 VPC에 다시 연결한다.
#
# private_zone_id 를 이름 대신 고정하는 이유 — 계정에 이름이 같은 private
# zone이 2개 있었다(2026-09-27 확인). 이름 기반 data 조회로는 "multiple
# Route 53 Hosted Zones matched" 로 aws-core 전체가 plan 단계에서 실패했다.
#
#   Z056721513V17DUDMWKXV — CallerReference jiho-test-cd-20260915-1025.
#     `aws route53 get-hosted-zone` 로 확인한 결과 그 시점의 실제 VPC
#     (vpc-010a8cba03c713593)와 연결돼 있던 쪽 — 이게 실제로 쓰이는 zone
#     (env/main.tf 의 private_zone_id).
#   Z01100642EPOEWRA969XL — CallerReference terraform-<random>, 코멘트
#     "Managed by Terraform". 예전에 aws_route53_zone 리소스로 Terraform이
#     만들었다가 코드에서 빠진 뒤 실제로는 안 지워진 고아 zone. 존재하지
#     않는 VPC에 연결돼 있어 아무 root의 state 도 참조하지 않는다 — 지워도
#     안전하다(AWS 콘솔/CLI 에서 수동으로).
#
# zone 자체는 Terraform 리소스가 아니라 aws-core 를 destroy/재생성해도
# zone_id 는 안 바뀐다 — VPC 만 바뀌고 이 association 이 매번 다시 붙여준다.
resource "aws_route53_zone_association" "boa_internal" {
  zone_id    = module.environment.private_zone_id
  vpc_id     = module.network.vpc_id
  vpc_region = module.environment.aws_region
}

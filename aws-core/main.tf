# =========================================================
# Network
# - 기존 VPC를 재사용한다. VPC 자체는 Terraform이 생성하지 않는다.
# - vpc-0a36febf3057e5da0: 192.168.0.0/16
# =========================================================

module "network" {
  source = "../aws-modules/network"

  project_name = "boa"
  cluster_name = "boa-eks"

  vpc_id = "vpc-0a36febf3057e5da0"

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

  # ElastiCache 전용. 기존에 쓰는 대역은 0·1·2·3·8·9·16·17 이라 24·25 가 비어 있다.
  cache_subnet_cidrs = [
    "192.168.24.0/24",
    "192.168.25.0/24"
  ]
}


data "aws_route53_zone" "boa_internal" {
  name         = "boa.internal."
  private_zone = true
}

resource "aws_route53_zone_association" "boa_internal" {
  zone_id    = data.aws_route53_zone.boa_internal.zone_id
  vpc_id     = module.network.vpc_id
  vpc_region = "ap-northeast-2"
}

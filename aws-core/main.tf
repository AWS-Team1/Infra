# =========================================================
# Network
# - VPC / IGW 는 기존 것을 재사용한다 (생성하지 않음)
#   vpc-07194d5f908bac7cf : 192.168.0.0/16
#   기존 퍼블릭 서브넷 192.168.0.0/24, 192.168.1.0/24 는 건드리지 않는다
# =========================================================

module "network" {
  source = "../aws-modules/network"

  project_name = "boa"
  cluster_name = "boa-eks"

  vpc_id                 = "vpc-07194d5f908bac7cf"
  s3_gateway_endpoint_id = "vpce-0853a7dfbfac3dd62"

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

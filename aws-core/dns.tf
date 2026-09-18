# 기존 boa.internal Private Hosted Zone을 새 VPC에 연결한다.
# Zone 자체는 공용 자산이라 생성하지 않고 association만 aws-core가 소유한다.
data "aws_route53_zone" "boa_internal" {
  name         = "boa.internal."
  private_zone = true
}

resource "aws_route53_zone_association" "boa_internal" {
  zone_id    = data.aws_route53_zone.boa_internal.zone_id
  vpc_id     = module.network.vpc_id
  vpc_region = "ap-northeast-2"
}

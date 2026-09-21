# 운영 VPC와 완전히 분리된 Valkey 검증용 VPC다.
resource "aws_vpc" "test" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "boa-test-vpc"
    Environment = "test"
  }
}

module "network" {
  source = "../aws-modules/network"

  project_name = "boa-test"
  cluster_name = "boa-test-eks"

  vpc_id = aws_vpc.test.id

  availability_zones = [
    "ap-northeast-2a",
    "ap-northeast-2c"
  ]

  public_subnet_cidrs = [
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]

  private_subnet_cidrs = [
    "10.0.8.0/24",
    "10.0.9.0/24"
  ]

  db_subnet_cidrs = [
    "10.0.16.0/24",
    "10.0.17.0/24"
  ]

  cache_subnet_cidrs = [
    "10.0.24.0/24",
    "10.0.25.0/24"
  ]
}

resource "aws_route53_zone" "test_internal" {
  name = "test.boa.internal"

  vpc {
    vpc_id = aws_vpc.test.id
  }

  tags = {
    Name        = "boa-test-internal-zone"
    Environment = "test"
  }
}

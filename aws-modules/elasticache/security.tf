# =========================================================
# ElastiCache Security Group
# =========================================================
# db SG 와 같은 이유로 CIDR 허용을 쓴다.
# aws-cache 루트가 aws-eks 를 참조하지 않는다.

# Valkey 앞단 SG. aws_elasticache_serverless_cache 의 security_group_ids 로 들어간다.
resource "aws_security_group" "cache" {
  name        = "${var.project_name}-cache-sg"
  description = "Security group for ElastiCache Valkey"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-cache-sg"
  }
}

# 프라이빗 서브넷 CIDR 마다 Serverless Valkey의 primary/read 포트
# 6379-6380 인바운드를 하나씩 연다. 일부 cluster client는 replica read를
# 사용하지 않아도 토폴로지 초기화 중 두 포트에 모두 연결한다.
resource "aws_vpc_security_group_ingress_rule" "cache_valkey" {
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = aws_security_group.cache.id

  cidr_ipv4   = each.value
  from_port   = 6379
  to_port     = 6380
  ip_protocol = "tcp"

  description = "Allow Serverless Valkey 6379-6380 from private subnet ${each.value}"

  tags = {
    Name = "${var.project_name}-cache-in-6379-6380-${each.value}"
  }
}

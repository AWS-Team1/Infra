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

# 프라이빗 서브넷 CIDR 마다 6379 인바운드를 하나씩 연다. db SG 와 같은 방식이다.
resource "aws_vpc_security_group_ingress_rule" "cache_valkey" {
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = aws_security_group.cache.id

  cidr_ipv4   = each.value
  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  description = "Allow Valkey from private subnet ${each.value}"

  tags = {
    Name = "${var.project_name}-cache-in-6379-${each.value}"
  }
}

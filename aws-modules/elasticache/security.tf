# =========================================================
# ElastiCache Security Group
# =========================================================
# db SG 와 같은 이유로 CIDR 허용을 쓴다.
# aws-cache 루트가 aws-eks 를 참조하지 않는다.

resource "aws_security_group" "cache" {
  name        = "${var.project_name}-cache-sg"
  description = "Security group for ElastiCache Valkey"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-cache-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cache_valkey" {
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = aws_security_group.cache.id

  cidr_ipv4   = each.value
  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  description = "Allow Valkey from private subnet ${each.value}"
}

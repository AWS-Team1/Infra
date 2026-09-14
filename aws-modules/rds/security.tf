# ===================================================
# DATABASE SECURITY GROUP
# ===================================================
# 인바운드를 EKS 클러스터 SG 참조가 아니라 프라이빗 서브넷 CIDR 로 연다.
# aws-rds 루트가 aws-eks 를 알 필요가 없어진다.
# 느슨해진 경계는 NACL 로 보완한다 (별도 과제).

# RDS 앞단 SG. aws_db_instance 의 vpc_security_group_ids 로 들어간다.
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for PostgreSQL RDS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# 프라이빗 서브넷 CIDR 마다 5432 인바운드를 하나씩 연다.
# EKS 클러스터 SG 를 참조하지 않으므로 aws-rds 루트가 aws-eks 를 몰라도 된다.
resource "aws_vpc_security_group_ingress_rule" "db_postgresql" {
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = aws_security_group.db.id

  cidr_ipv4   = each.value
  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  description = "Allow PostgreSQL from private subnet ${each.value}"

  tags = {
    Name = "${var.project_name}-db-in-5432-${each.value}"
  }
}

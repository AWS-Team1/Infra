# ===================================================
# ALB SECURITY GROUP
# ===================================================

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id


  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}


# ===================================================
# EKS / APPLICATION SECURITY GROUP
# ===================================================

# resource "aws_security_group" "eks" {
#   name        = "${var.project_name}-eks-sg"
#   description = "Security group for EKS worker nodes"
#   vpc_id      = var.vpc_id

#   tags = {
#     Name = "${var.project_name}-eks-sg"
#   }
# }


# ===================================================
# DATABASE SECURITY GROUP
# ===================================================

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for PostgreSQL RDS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# security group과 




# ===================================================
# ALB INGRESS
# ===================================================

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  description = "Allow HTTP from Internet"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow HTTPS from Internet"
}


# ===================================================
# ALB EGRESS -> EKS
# ===================================================

# resource "aws_vpc_security_group_egress_rule" "alb_to_eks" {
#   security_group_id = aws_security_group.alb.id

#   referenced_security_group_id = aws_security_group.eks.id

#   from_port   = 80
#   to_port     = 80
#   ip_protocol = "tcp"

#   description = "Allow ALB traffic to EKS workloads"
# }


# ===================================================
# EKS INGRESS <- ALB
# ===================================================

# resource "aws_vpc_security_group_ingress_rule" "eks_from_alb" {
#   security_group_id = aws_security_group.eks.id

#   referenced_security_group_id = aws_security_group.alb.id

#   from_port   = 80
#   to_port     = 80
#   ip_protocol = "tcp"

#   description = "Allow HTTP from ALB"
# }


# ===================================================
# EKS EGRESS
# ===================================================

# resource "aws_vpc_security_group_egress_rule" "eks_all" {
#   security_group_id = aws_security_group.eks.id

#   cidr_ipv4   = "0.0.0.0/0"
#   ip_protocol = "-1"

#   description = "Allow outbound traffic from EKS"
# }


# ===================================================
# DB INGRESS <- EKS
# ===================================================

resource "aws_vpc_security_group_ingress_rule" "db_postgresql" {
  security_group_id = aws_security_group.db.id

  referenced_security_group_id = var.eks_cluster_security_group_id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  description = "Allow PostgreSQL from EKS"
}

# =========================================================
# ElastiCache Security Group
# - ElastiCache Serverless Valkey에 연결
# =========================================================

resource "aws_security_group" "cache" {
  name        = "${var.project_name}-cache-sg"
  description = "Security group for ElastiCache Valkey"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-cache-sg"
  }
}


# =========================================================
# EKS → ElastiCache
# - EKS Cluster Security Group에서 오는
#   TCP 6379 연결만 허용
# =========================================================

resource "aws_vpc_security_group_ingress_rule" "cache_valkey" {
  security_group_id = aws_security_group.cache.id

  referenced_security_group_id = var.eks_cluster_security_group_id

  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  description = "Allow Valkey from EKS"
}

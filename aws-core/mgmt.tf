# ============================================================================
# DATABASE MANAGEMENT HOST
#
# Private Subnet에서 상시 실행하며, 관리자의 로컬 DBeaver 연결을
# SSM Port Forwarding으로 db.boa.internal:5432에 전달한다.
# Public IP, SSH Key, 인바운드 보안 그룹 규칙은 사용하지 않는다.
# ============================================================================

data "aws_iam_policy_document" "mgmt_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mgmt" {
  name               = "boa-mgmt-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.mgmt_assume_role.json

  tags = {
    Name    = "boa-mgmt-ssm-role"
    Purpose = "database-management"
  }
}

# SSM 관리형 노드 등록과 Session Manager 통신에 필요한 최소 관리형 정책이다.
resource "aws_iam_role_policy_attachment" "mgmt_ssm" {
  role       = aws_iam_role.mgmt.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "mgmt" {
  name = "boa-mgmt-instance-profile"
  role = aws_iam_role.mgmt.name

  tags = {
    Name    = "boa-mgmt-instance-profile"
    Purpose = "database-management"
  }
}

resource "aws_security_group" "mgmt" {
  name        = "boa-mgmt-sg"
  description = "Security group for the BOA database management host"
  vpc_id      = module.network.vpc_id

  tags = {
    Name    = "boa-mgmt-sg"
    Purpose = "database-management"
  }
}

# 기존 NAT Gateway를 통해 AWS Systems Manager API와 통신한다.
resource "aws_vpc_security_group_egress_rule" "mgmt_https" {
  security_group_id = aws_security_group.mgmt.id

  description = "Allow HTTPS to AWS Systems Manager through the NAT Gateway"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = {
    Name = "boa-mgmt-out-https"
  }
}

# db.boa.internal이 가리키는 PostgreSQL RDS로만 DB 포트 통신을 허용한다.
resource "aws_vpc_security_group_egress_rule" "mgmt_postgresql" {
  security_group_id = aws_security_group.mgmt.id

  description = "Allow PostgreSQL to the BOA VPC"
  cidr_ipv4   = module.network.vpc_cidr
  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  tags = {
    Name = "boa-mgmt-out-postgresql"
  }
}

resource "aws_instance" "mgmt" {
  # 기존 boa-bastion과 동일한 Amazon Linux 2023 AMI를 재사용한다.
  ami           = "ami-0c97793ee5ea0967f"
  instance_type = "t3.micro"

  subnet_id                   = module.network.private_subnet_ids[0]
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.mgmt.id]
  iam_instance_profile        = aws_iam_instance_profile.mgmt.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name    = "boa-mgmt"
    Purpose = "database-management"
  }

  depends_on = [aws_iam_role_policy_attachment.mgmt_ssm]
}

output "mgmt_instance_id" {
  description = "EC2 instance ID used as the SSM Port Forwarding target"
  value       = aws_instance.mgmt.id
}

output "mgmt_private_ip" {
  description = "Private IPv4 address of the database management host"
  value       = aws_instance.mgmt.private_ip
}

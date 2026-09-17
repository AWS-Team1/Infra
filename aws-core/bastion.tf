# ============================================================================
# TEMPORARY BASTION
#
# DB 관리 작업이 끝나면 이 파일의 리소스를 한 번에 제거할 수 있도록
# Bastion 관련 데이터 소스, 보안 그룹, 인스턴스, 출력값을 여기에 모은다.
# 별도의 시작 스크립트(user_data)는 사용하지 않는다.
# ============================================================================

# Amazon Linux 2023 x86_64의 최신 공식 AMI를 조회한다.
data "aws_ami" "bastion" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# AWS에 이미 등록된 키페어를 재사용한다. 새 개인 키는 만들지 않는다.
data "aws_key_pair" "bastion" {
  key_name = "boa-bastion"
}

resource "aws_security_group" "bastion" {
  name        = "boa-bastion-sg"
  description = "Temporary security group for the BOA bastion host"
  vpc_id      = module.network.vpc_id

  tags = {
    Name      = "boa-bastion-sg"
    Purpose   = "temporary-db-access"
    Temporary = "true"
  }
}

# WARNING: 임시 구축 편의를 위한 전체 IPv4 SSH 허용이다.
# 사용이 끝나면 Bastion을 제거하고, 운영 중에는 가능한 한 관리자 공인 IP/32로 제한한다.
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id

  description = "TEMPORARY - allow SSH from anywhere"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"

  tags = {
    Name      = "boa-bastion-in-ssh"
    Temporary = "true"
  }
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id

  description = "Allow bastion outbound traffic"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = {
    Name      = "boa-bastion-out-all"
    Temporary = "true"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.bastion.id
  instance_type = "t3.micro"

  subnet_id                   = module.network.public_subnet_ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = data.aws_key_pair.bastion.key_name

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
    Name      = "boa-bastion"
    Purpose   = "temporary-db-access"
    Temporary = "true"
  }
}

# aws-rds의 DB 보안 그룹에서 이 SG를 소스로 TCP 5432를 허용할 때 사용한다.
output "bastion_security_group_id" {
  description = "Security group ID to allow as a PostgreSQL source"
  value       = aws_security_group.bastion.id
}

output "bastion_instance_id" {
  description = "Temporary bastion EC2 instance ID"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IPv4 address used for SSH access"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IPv4 address used for internal database access"
  value       = aws_instance.bastion.private_ip
}

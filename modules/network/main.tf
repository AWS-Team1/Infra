# ===================================================
#       기존 VPC 참조 (생성하지 않는다)
# ===================================================
# VPC 는 이미 존재하는 것을 재사용한다.
# IGW 는 기존 것을 삭제했으므로 이 모듈이 새로 만든다 (VPC 당 1개 제한).

data "aws_vpc" "main" {
  id = var.vpc_id
}

resource "aws_internet_gateway" "main" {
  vpc_id = data.aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}


# ===================================================
#       SUBNET
# ===================================================

resource "aws_subnet" "public_a" {
  vpc_id                  = data.aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[0]
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-public-a"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = data.aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[1]
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-public-c"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[0]
  availability_zone = var.availability_zones[0]

  tags = {
    Name                              = "${var.project_name}-private-a"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }
}

resource "aws_subnet" "private_c" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[1]
  availability_zone = var.availability_zones[1]

  tags = {
    Name                              = "${var.project_name}-private-c"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }
}

resource "aws_subnet" "db_a" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[0]
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.project_name}-db-a"
  }
}

resource "aws_subnet" "db_c" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[1]
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.project_name}-db-c"
  }
}


# ===================================================
#       PUBLIC ROUTE TABLE (기존 IGW 로 나간다)
# ===================================================

resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# ===================================================
#       ELASTIC IP, NAT GATEWAY, ROUTE TABLE, CONNECTION
# ===================================================
resource "aws_eip" "nat_a" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-a"
  }
}

resource "aws_eip" "nat_c" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-c"
  }
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-a"
  }
}

resource "aws_nat_gateway" "nat_c" {
  allocation_id = aws_eip.nat_c.id
  subnet_id     = aws_subnet.public_c.id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-c"
  }
}


resource "aws_route_table" "private_a" {
  vpc_id = data.aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }

  tags = {
    Name = "${var.project_name}-private-rt-a"
  }
}

resource "aws_route_table" "private_c" {
  vpc_id = data.aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_c.id
  }

  tags = {
    Name = "${var.project_name}-private-rt-c"
  }
}


resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private_c.id
}


# ===================================================
#       S3 GATEWAY ENDPOINT 연결
# ===================================================
# 엔드포인트 자체는 기존 것을 그대로 쓰고, 새 private route table 에
# 경로만 추가한다. var.s3_gateway_endpoint_id 가 비면 건너뛴다.

resource "aws_vpc_endpoint_route_table_association" "s3_private_a" {
  count = var.s3_gateway_endpoint_id == "" ? 0 : 1

  vpc_endpoint_id = var.s3_gateway_endpoint_id
  route_table_id  = aws_route_table.private_a.id
}

resource "aws_vpc_endpoint_route_table_association" "s3_private_c" {
  count = var.s3_gateway_endpoint_id == "" ? 0 : 1

  vpc_endpoint_id = var.s3_gateway_endpoint_id
  route_table_id  = aws_route_table.private_c.id
}

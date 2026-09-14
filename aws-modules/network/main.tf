# ===================================================
#       기존 VPC 참조 (생성하지 않는다)
# ===================================================
# VPC 는 이미 존재하는 것을 재사용한다.
# IGW 는 기존 것을 삭제했으므로 이 모듈이 새로 만든다 (VPC 당 1개 제한).

# 재사용할 기존 VPC. 아래 모든 서브넷·라우팅 테이블이 이 VPC 에 들어간다.
data "aws_vpc" "main" {
  id = var.vpc_id
}

# 인터넷 게이트웨이. 퍼블릭 라우팅 테이블의 0.0.0.0/0 목적지이고,
# NAT 게이트웨이가 이걸 거쳐 나간다.
resource "aws_internet_gateway" "main" {
  vpc_id = data.aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}


# ===================================================
#       SUBNET
# ===================================================

# 퍼블릭 a — NAT 게이트웨이와 ops ALB 가 여기 들어간다.
# kubernetes.io/role/elb 태그로 ALB 컨트롤러가 인터넷 향 ALB 자리를 찾는다.
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

# 퍼블릭 c — 위와 같은 역할의 다른 가용영역. ALB 는 최소 2개 AZ 를 요구한다.
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

# 프라이빗 a — EKS 노드와 파드가 여기 뜬다. VPC CNI 라 파드도 이 대역의 IP 를 받는다.
# internal-elb 태그는 내부용 ALB/NLB 탐색에, karpenter.sh/discovery 는
# Karpenter 가 노드를 띄울 서브넷을 찾는 데 쓴다.
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

# 프라이빗 c — 위와 같은 역할의 다른 가용영역.
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

# DB a — RDS 전용. aws-rds 루트가 db_subnet_ids 로 받아 서브넷 그룹을 만든다.
# 라우팅 테이블을 붙이지 않아 메인 RT(local 만)를 상속한다 — 외부로 나가지 않는다.
resource "aws_subnet" "db_a" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[0]
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.project_name}-db-a"
  }
}

# DB c — Multi-AZ RDS 는 서로 다른 가용영역의 서브넷 2개를 요구한다.
resource "aws_subnet" "db_c" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[1]
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.project_name}-db-c"
  }
}

# 캐시 a — ElastiCache 전용. aws-cache 루트가 cache_subnet_ids 로 받는다.
# 프라이빗과 분리하는 이유는 둘이다 —
#   1) VPC CNI 라 파드가 프라이빗 IP 를 하나씩 먹어 /24 가 빨리 준다
#   2) NACL 은 서브넷 단위라 같은 서브넷이면 파드와 캐시를 구분할 수 없다
# db 서브넷과 마찬가지로 라우팅 테이블을 붙이지 않는다 — 외부로 나가지 않는다.
resource "aws_subnet" "cache_a" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = var.cache_subnet_cidrs[0]
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.project_name}-cache-a"
  }
}

# 캐시 c — ElastiCache 서브넷 그룹도 서로 다른 가용영역 2개를 요구한다.
resource "aws_subnet" "cache_c" {
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = var.cache_subnet_cidrs[1]
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.project_name}-cache-c"
  }
}


# ===================================================
#       PUBLIC ROUTE TABLE (기존 IGW 로 나간다)
# ===================================================

# 퍼블릭 서브넷용 라우팅 테이블. 기본 경로를 IGW 로 보낸다.
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

# 퍼블릭 a 를 위 라우팅 테이블에 연결.
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# 퍼블릭 c 를 위 라우팅 테이블에 연결. 퍼블릭 둘은 RT 를 공유한다.
resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# ===================================================
#       ELASTIC IP, NAT GATEWAY, ROUTE TABLE, CONNECTION
# ===================================================
# 프라이빗은 AZ 별로 NAT 를 따로 둔다. 한쪽 AZ 가 죽어도 다른 쪽이 산다.

# NAT a 가 쓸 고정 공인 IP.
resource "aws_eip" "nat_a" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-a"
  }
}

# NAT c 가 쓸 고정 공인 IP.
resource "aws_eip" "nat_c" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-c"
  }
}

# NAT a — 퍼블릭 a 에 놓고 프라이빗 a 의 아웃바운드를 받는다.
# IGW 가 VPC 에 붙기 전에 만들어지지 않도록 depends_on 을 건다.
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-a"
  }
}

# NAT c — 퍼블릭 c 에 놓고 프라이빗 c 의 아웃바운드를 받는다.
resource "aws_nat_gateway" "nat_c" {
  allocation_id = aws_eip.nat_c.id
  subnet_id     = aws_subnet.public_c.id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-c"
  }
}


# 프라이빗 a 용 라우팅 테이블. 기본 경로를 같은 AZ 의 NAT 로 보낸다.
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

# 프라이빗 c 용 라우팅 테이블. AZ 별로 나눈 이유가 여기 있다 —
# 하나로 합치면 한쪽 NAT 장애가 양쪽 AZ 를 같이 끊는다.
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


# 프라이빗 a 를 같은 AZ 의 라우팅 테이블에 연결.
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

# 프라이빗 c 를 같은 AZ 의 라우팅 테이블에 연결.
resource "aws_route_table_association" "private_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private_c.id
}


# ===================================================
#       S3 GATEWAY ENDPOINT 연결
# ===================================================
# 엔드포인트 자체는 기존 것을 그대로 쓰고, 새 private route table 에
# 경로만 추가한다. var.s3_gateway_endpoint_id 가 비면 건너뛴다.

# 프라이빗 a 의 S3 트래픽을 NAT 대신 게이트웨이 엔드포인트로 보낸다.
# NAT 데이터 처리 요금을 아끼고 트래픽이 AWS 백본 안에 머문다.
resource "aws_vpc_endpoint_route_table_association" "s3_private_a" {
  count = var.s3_gateway_endpoint_id == "" ? 0 : 1

  vpc_endpoint_id = var.s3_gateway_endpoint_id
  route_table_id  = aws_route_table.private_a.id
}

# 프라이빗 c 도 같은 엔드포인트에 연결.
resource "aws_vpc_endpoint_route_table_association" "s3_private_c" {
  count = var.s3_gateway_endpoint_id == "" ? 0 : 1

  vpc_endpoint_id = var.s3_gateway_endpoint_id
  route_table_id  = aws_route_table.private_c.id
}

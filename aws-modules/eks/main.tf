# ===================================================
# CLOUDWATCH LOG GROUP FOR EKS CONTROL PLANE
# ===================================================

# 컨트롤 플레인 로그가 쌓일 곳. EKS 가 자동 생성하기 전에 Terraform 이 먼저 만들어
# 보존 기간을 지정한다. 클러스터가 이걸 depends_on 으로 기다린다.
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.control_plane_log_retention_days

  tags = {
    Name = "${var.cluster_name}-control-plane-logs"
  }
}


# ===================================================
# EKS CLUSTER
# ===================================================

# 컨트롤 플레인. 프라이빗 서브넷에만 배치하고 퍼블릭 엔드포인트는
# var.public_access_cidrs 로 좁힌다. 역할은 eks-iam 모듈이 만든 것을 받는다.
# 감사 로그 5종을 위 로그 그룹으로 보낸다.
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  vpc_config {
    subnet_ids = var.private_subnet_ids

    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    authentication_mode = "API"
  }

  depends_on = [
    aws_cloudwatch_log_group.eks
  ]

  tags = {
    Name = var.cluster_name
  }
}


# EKS 가 자동 생성한 클러스터 SG 에 Karpenter 탐색 태그를 붙인다.
# 그 SG 는 Terraform 이 만든 게 아니라서 aws_ec2_tag 로 태그만 관리한다.
resource "aws_ec2_tag" "karpenter_cluster_sg_discovery" {
  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id

  key   = "karpenter.sh/discovery"
  value = var.cluster_name
}


# ===================================================
# EKS MANAGED NODE GROUP
# ===================================================

# 애플리케이션 파드가 뜰 워커 노드. 프라이빗 서브넷에 배치된다.
# 역할은 eks-iam 의 node_role_arn 이고, 그 output 이 정책 부착 완료를 보장한다.
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = var.node_role_arn

  subnet_ids = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type

  ami_type  = "AL2023_x86_64_STANDARD"
  disk_size = var.node_disk_size

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = var.node_max_unavailable
  }

  node_repair_config {
    enabled = true
  }

  tags = {
    Name = var.node_group_name
  }
}




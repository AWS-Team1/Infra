# ===================================================
# CLOUDWATCH LOG GROUP FOR EKS CONTROL PLANE
# ===================================================

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

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
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
    aws_iam_role_policy_attachment.cluster_eks_policy,
    aws_cloudwatch_log_group.eks
  ]

  tags = {
    Name = var.cluster_name
  }
}


resource "aws_ec2_tag" "karpenter_cluster_sg_discovery" {
  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id

  key   = "karpenter.sh/discovery"
  value = var.cluster_name
}


# ===================================================
# EKS MANAGED NODE GROUP
# ===================================================

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.node.arn

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

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_cni
  ]

  tags = {
    Name = var.node_group_name
  }
}




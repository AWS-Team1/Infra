# aws-core 가 만든 VPC·서브넷을 읽는다. 이 루트는 aws-rds·aws-cache 를 참조하지 않는다.
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

module "eks_iam" {
  source = "../aws-modules/eks-iam"

  project_name = "boa"
  cluster_name = "boa-eks"
  region       = "ap-northeast-2"
}

module "eks" {
  source = "../aws-modules/eks"

  project_name       = "boa"
  cluster_name       = "boa-eks"
  kubernetes_version = "1.36"

  private_subnet_ids = data.terraform_remote_state.core.outputs.private_subnet_ids

  public_access_cidrs = var.public_access_cidrs

  node_group_name = "boa-eks-node-group"

  node_instance_types = [
    "t3.large"
  ]
  region = "ap-northeast-2"

  node_capacity_type = "ON_DEMAND"
  node_disk_size     = 30

  node_min_size     = 2
  node_desired_size = 2
  node_max_size     = 2

  node_max_unavailable = 1

  control_plane_log_retention_days = 30

  cluster_admin_role_arns = [
    var.github_terraform_role_arn,
    var.code_server_role_arn,
  ]

  console_user_group_name = var.console_user_group_name

  cluster_role_arn        = module.eks_iam.cluster_role_arn
  node_role_arn           = module.eks_iam.node_role_arn
  karpenter_role_arn      = module.eks_iam.karpenter_role_arn
  ebs_csi_role_arn        = module.eks_iam.ebs_csi_role_arn
  bank_of_anthos_role_arn = module.eks_iam.bank_of_anthos_role_arn
}

# ALB 컨트롤러는 Terraform 소유를 유지한다 (설계 문서 결정 6).
# 분리는 개선 과제다.
module "aws_load_balancer_controller" {
  source = "../aws-modules/aws-load-balancer-controller"

  cluster_name = module.eks.cluster_name
  region       = "ap-northeast-2"
  vpc_id       = data.terraform_remote_state.core.outputs.vpc_id

  depends_on = [
    module.eks
  ]
}

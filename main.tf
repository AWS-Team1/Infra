module "network" {
  source = "./modules/network"

  project_name = "project"

  vpc_cidr = "10.0.0.0/16"

  availability_zones = [
    "ap-northeast-2a",
    "ap-northeast-2c"
  ]

  public_subnet_cidrs = [
    "10.0.0.0/24",
    "10.0.1.0/24"
  ]

  private_subnet_cidrs = [
    "10.0.8.0/24",
    "10.0.9.0/24"
  ]

  db_subnet_cidrs = [
    "10.0.16.0/24",
    "10.0.17.0/24"
  ]
}



module "security" {
  source = "./modules/security"

  project_name = "project"
  vpc_id       = module.network.vpc_id

  eks_cluster_security_group_id = module.eks.cluster_security_group_id
}



module "eks" {
  source = "./modules/eks"

  cluster_name       = "project-eks"
  kubernetes_version = "1.36"

  private_subnet_ids = module.network.private_subnet_ids

  public_access_cidrs = [
    "15.165.176.99/32"
  ]

  node_group_name = "project-eks-node-group"

  node_instance_types = [
    "t3.medium"
  ]
  region = "ap-northeast-2"

  node_capacity_type = "ON_DEMAND"
  node_disk_size     = 30

  node_min_size     = 2
  node_desired_size = 2
  node_max_size     = 2

  node_max_unavailable = 1

  control_plane_log_retention_days = 30

  code_server_role_arn = var.code_server_role_arn
}



module "rds" {
  source = "./modules/rds"

  project_name = "project"

  db_identifier = "project-postgres"
  db_name       = "projectdb"
  db_username   = "project_admin"

  engine_version = "16.14"
  instance_class = "db.t4g.micro"

  allocated_storage     = 30
  max_allocated_storage = 100

  db_subnet_ids        = module.network.db_subnet_ids
  db_security_group_id = module.security.db_sg_id

  backup_retention_period                = 7
  monitoring_interval                    = 60
  performance_insights_retention_period  = 7
  enhanced_monitoring_log_retention_days = 7
}



# =========================================================
# ElastiCache Serverless Valkey
# - 로그인 Session / Cache 용도
# =========================================================

module "elasticache" {
  source = "./modules/elasticache"

  project_name = "project"

  # Cache / RBAC User 이름
  cache_name = "project-valkey"
  user_name  = "project-app"

  # EKS Private Subnet A/C 공유
  subnet_ids = module.network.private_subnet_ids

  # Security 모듈에서 생성한 Cache SG
  security_group_id = module.security.cache_sg_id

  # Phase 1 테스트용 낮은 사용량 상한
  max_data_storage    = 1
  max_ecpu_per_second = 1000
}


module "aws_load_balancer_controller" {
  source = "./modules/aws-load-balancer-controller"

  cluster_name = module.eks.cluster_name
  region       = "ap-northeast-2"
  vpc_id       = module.network.vpc_id
  depends_on = [
    module.eks
  ]
}

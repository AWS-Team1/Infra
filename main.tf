# =========================================================
# Network
# - VPC / IGW 는 기존 것을 재사용한다 (생성하지 않음)
#   vpc-07194d5f908bac7cf : 192.168.0.0/16
#   기존 퍼블릭 서브넷 192.168.0.0/24, 192.168.1.0/24 는 건드리지 않는다
# =========================================================

module "network" {
  source = "./aws-modules/network"

  project_name = "boa"
  cluster_name = "boa-eks"

  vpc_id                 = "vpc-07194d5f908bac7cf"
  s3_gateway_endpoint_id = "vpce-0853a7dfbfac3dd62"

  availability_zones = [
    "ap-northeast-2a",
    "ap-northeast-2c"
  ]

  public_subnet_cidrs = [
    "192.168.2.0/24",
    "192.168.3.0/24"
  ]

  private_subnet_cidrs = [
    "192.168.8.0/24",
    "192.168.9.0/24"
  ]

  db_subnet_cidrs = [
    "192.168.16.0/24",
    "192.168.17.0/24"
  ]
}



module "security" {
  source = "./modules/security"

  project_name = "boa"
  vpc_id       = module.network.vpc_id

  eks_cluster_security_group_id = module.eks.cluster_security_group_id
}



module "eks" {
  source = "./aws-modules/eks"

  project_name       = "boa"
  cluster_name       = "boa-eks"
  kubernetes_version = "1.36"

  private_subnet_ids = module.network.private_subnet_ids

  public_access_cidrs = [
    "15.165.176.99/32"
  ]

  node_group_name = "boa-eks-node-group"

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
  source = "./aws-modules/rds"

  project_name = "boa"

  db_identifier = "boa-postgres"
  db_name       = "boadb"
  db_username   = "boa_admin"

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

  # RDSOSMetrics 는 계정·리전 공용 고정 이름. 기존 스택이 이미 보유 중이라 생성하지 않는다.
  create_os_metrics_log_group = false
}



# =========================================================
# ElastiCache Serverless Valkey
# - 로그인 Session / Cache 용도
# =========================================================

module "elasticache" {
  source = "./aws-modules/elasticache"

  project_name = "boa"

  # Cache / RBAC User 이름
  cache_name = "boa-valkey"
  user_name  = "boa-app"

  # EKS Private Subnet A/C 공유
  subnet_ids = module.network.private_subnet_ids

  # Security 모듈에서 생성한 Cache SG
  security_group_id = module.security.cache_sg_id

  # Phase 1 테스트용 낮은 사용량 상한
  max_data_storage    = 1
  max_ecpu_per_second = 1000
}


module "aws_load_balancer_controller" {
  source = "./aws-modules/aws-load-balancer-controller"

  cluster_name = module.eks.cluster_name
  region       = "ap-northeast-2"
  vpc_id       = module.network.vpc_id
  depends_on = [
    module.eks
  ]
}

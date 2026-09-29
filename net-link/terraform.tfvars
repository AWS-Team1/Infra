# 이 파일은 실제 구축 입력으로 Git에서 관리한다.
# VPC/라우트 테이블/네트워크/Router/Cloud SQL 주소는 state와 data source에서 조회한다.

project_name   = "boa"
aws_region     = "ap-northeast-2"
gcp_project_id = "kdt4-1-506106"

default_tags = {
  Project   = "boa"
  Component = "net-link"
  ManagedBy = "terraform"
  Repo      = "AWS-Team1/Infra"
}

# data.terraform_remote_state 조회 위치
remote_state_bucket    = "boa-terraform-state-6416"
remote_state_region    = "ap-northeast-2"
aws_core_state_key     = "aws/core/terraform.tfstate"
gcp_core_state_key     = "gcp/core/terraform.tfstate"
gcp_cloudsql_state_key = "gcp/cloudsql/terraform.tfstate"

# AWS route table data source의 Name 필터
aws_private_route_table_name_patterns = ["boa-private-rt-*"]
aws_public_route_table_names          = ["boa-public-rt"]

aws_asn = 64512
gcp_asn = 64514

ike_version               = 2
advertised_route_priority = 100
gcp_advertised_groups     = ["ALL_SUBNETS"]

# Cloud SQL /32는 gcp-cloudsql state의 private_ip_address로 자동 추가된다.
gcp_additional_advertised_ip_ranges = []

tunnel_inside_cidrs = {
  "0" = ["169.254.10.0/30", "169.254.10.4/30"]
  "1" = ["169.254.10.8/30", "169.254.10.12/30"]
}

# 실제 적용 전 기존 네 터널의 PSK를 정확히 입력한다.
# 새 값으로 바꾸면 VPN 터널 교체/단절이 발생하며, 이 파일에 입력한 값은 Git 이력에 남는다.
tunnel_preshared_keys = {
  "0" = ["Index1203", "Index1203"]
  "1" = ["Index1203", "Index1203"]
}

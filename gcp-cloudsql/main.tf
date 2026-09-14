# =========================================================
# gcp-cloudsql — AWS DMS 의 복제 대상
# gcp-core 만 참조한다. gcp-gke 를 알지 못한다(1단 평면).
# =========================================================

data "terraform_remote_state" "gcp_core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "gcp/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

module "cloudsql" {
  source = "../gcp-modules/cloudsql"

  project_name  = "boa"
  instance_name = "boa-postgres-dr"
  region        = var.region

  # AWS RDS 가 postgres 16.14 다. 메이저를 맞춘다.
  database_version = "POSTGRES_16"

  # Pilot Light — 대기 중에는 소형 · 단일 영역.
  # 페일오버 후 tier 를 올리고 availability_type 을 REGIONAL 로 바꾼다.
  tier              = "db-custom-1-3840"
  availability_type = "ZONAL"
  disk_size         = 20

  network_id     = data.terraform_remote_state.gcp_core.outputs.network_id
  psa_connection = data.terraform_remote_state.gcp_core.outputs.psa_connection

  # AWS 쪽 db-bootstrap Job 이 만드는 이름과 같아야 DMS 매핑이 단순해진다.
  app_database_names = ["accounts", "ledger"]

  dms_username = "dms_writer"
  dms_password = var.dms_password

  app_username = "boa_app"
  app_password = var.app_password

  deletion_protection = true
}

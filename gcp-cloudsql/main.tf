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

data "google_project" "current" {
  project_id = var.gcp_project_id
}

# 앱 계정 비밀번호는 apply 중 메모리에서만 만들고 state/파일에 남기지 않는다.
ephemeral "random_password" "accounts" {
  length  = 64
  special = false
}

ephemeral "random_password" "ledger" {
  length  = 64
  special = false
}

ephemeral "random_password" "bootstrap" {
  length  = 64
  special = false
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
  app_database_names = ["accountsdb", "ledgerdb"]

  dms_username = "dms_writer"
  dms_password = var.dms_password

  accounts_username  = "accounts_app"
  accounts_password  = ephemeral.random_password.accounts.result
  ledger_username    = "ledger_app"
  ledger_password    = ephemeral.random_password.ledger.result
  bootstrap_username = "boa_bootstrap"
  bootstrap_password = ephemeral.random_password.bootstrap.result

  # 재구축 런북에서 별도 해제 apply 없이 바로 destroy할 수 있게 한다.
  deletion_protection = false
}

# Kubernetes Secret 이름과 1:1로 대응하는 GCP Secret Manager 컨테이너다.
## 만약 기존에 secrects이 존재한다면 해당 컴포넌트를 resource --> data 컴포넌트로 변경해야 한다.


resource "google_secret_manager_secret" "app_database" {
  for_each  = toset(["accounts", "ledger"])
  secret_id = "boa-database-${each.key}"

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret" "database_bootstrap" {
  secret_id = "boa-database-bootstrap-password"

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}


#--data 리소스로 변경
#data "google_secret_manager_secret" "app_database" {
#  for_each  = toset(["accounts", "ledger"])
#  project   = var.gcp_project_id
#  secret_id = "boa-database-${each.key}"
#}

#data "google_secret_manager_secret" "database_bootstrap" {
#  project   = var.gcp_project_id
#  secret_id = "boa-database-bootstrap-password"
#}

# 각 생성된 시크릿에 DB별 비밀번호 업로드, 버전을 명시해줘서 변경시에 알수 있게 설정
resource "google_secret_manager_secret_version" "accounts" {
  secret                 = google_secret_manager_secret.app_database["accounts"].id
  secret_data_wo         = ephemeral.random_password.accounts.result
  secret_data_wo_version = 1
}

resource "google_secret_manager_secret_version" "ledger" {
  secret                 = google_secret_manager_secret.app_database["ledger"].id
  secret_data_wo         = ephemeral.random_password.ledger.result
  secret_data_wo_version = 1
}



resource "google_secret_manager_secret_version" "database_bootstrap" {
  secret                 = google_secret_manager_secret.database_bootstrap.id
  secret_data_wo         = ephemeral.random_password.bootstrap.result
  secret_data_wo_version = 1
}

# GKE SecretSync 전용 KSA에 두 DB 비밀번호를 읽을 권한만 준다.
resource "google_secret_manager_secret_iam_member" "gke" {
  for_each  = google_secret_manager_secret.app_database
  project   = var.gcp_project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${var.gcp_project_id}.svc.id.goog/subject/ns/bank-of-anthos/sa/bank-app-secret-sync"
}

resource "google_secret_manager_secret_iam_member" "gke_database_bootstrap" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.database_bootstrap.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${var.gcp_project_id}.svc.id.goog/subject/ns/bank-of-anthos/sa/bank-db-bootstrap"
}

# Cloud SQL 재생성으로 사설 IP가 바뀌어도 GitOps는 이 DNS 이름만 사용한다.
resource "google_dns_managed_zone" "database" {
  name        = "boa-gcp-internal"
  dns_name    = "gcp.boa.internal."
  description = "Private DNS for Bank of Anthos GCP services"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = data.terraform_remote_state.gcp_core.outputs.network_id
    }
  }
}

# 테라폼 destroy / apply시마다 RDS 이름이 바뀌기에 DNS 호스트영역을 만들고
# 내부적으로 DB에 대한 A레코드를 등록 -> DB DNS명을 "db.gcp.boa.internal"로 고정시킴
resource "google_dns_record_set" "database" {
  name         = "db.gcp.boa.internal."
  managed_zone = google_dns_managed_zone.database.name
  type         = "A"
  ttl          = 60
  rrdatas      = [module.cloudsql.private_ip_address]
}

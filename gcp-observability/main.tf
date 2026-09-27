# =========================================================
# gcp-observability — 관측 스택의 GCP 측 리소스
#
# EKS와 대칭이 아니다. GKE는 다음이 이미 클러스터에 내장돼 있어서
# aws-observability가 만드는 것 중 상당수가 필요 없다(gcp-modules/gke의
# secret_manager_config·secret_sync_config, Workload Identity):
#   - ESO(External Secrets Operator) 상당 없음 — GKE 네이티브 SecretSync
#   - CloudWatch 로그그룹/데이터보호정책 상당 없음 — Cloud Logging 자동 수집
#   - ALB TargetGroupBinding 상당 없음 — GKE에는 Grafana를 두지 않는다
#     (gitops 03_manifests/overlays/gke/observability/에 grafana.yaml 없음)
#
# 이 root가 만드는 건 딱 하나 — gitops가 참조하는 세 KSA(쿠버네티스
# ServiceAccount: monitoring 네임스페이스의 observability-secret-sync·
# otel-collector, whatap-monitoring 네임스페이스의 whatap-credentials-sync)
# 에 Workload Identity로 GCP 권한을 주는 것뿐이다.
#
# GSA(Google Service Account)를 따로 만들지 않는다. gcp-cloudsql/main.tf의
# google_secret_manager_secret_iam_member.gke 와 같은 패턴 — KSA의 workload
# identity principal에 role을 직접 바인딩한다("신방식", GSA·어노테이션 불필요).
# gitops의 observability/rbac.yaml 이 이 방식을 전제로 SA 어노테이션을
# 비워 뒀다.
#
# whatap 시크릿(boa-whatap-application-license · boa-whatap-host ·
# boa-whatap-port)은 이 root가 만들지 않는다 — AWS의 /boa/observability/*
# 와 같은 원칙으로 콘솔에서 직접 만들어 채운다. 여기서는 그 세 시크릿을
# 읽을 권한만 부여한다.
# =========================================================

data "google_project" "current" {
  project_id = var.gcp_project_id
}

locals {
  workload_identity_pool = "${var.gcp_project_id}.svc.id.goog"

  # gitops의 03_manifests/overlays/gke/observability/secrets.yaml,
  # rbac.yaml 과 반드시 일치해야 한다. 어긋나면 principal 이 안 맞아서
  # 권한이 조용히 안 먹는다.
  observability_namespace     = "monitoring"
  secret_sync_service_account = "observability-secret-sync"
  collector_service_account   = "otel-collector"

  whatap_secret_ids = [
    "boa-whatap-application-license",
    "boa-whatap-host",
    "boa-whatap-port",
  ]

  # whatap-monitoring 네임스페이스 — 와탭 쿠버네티스 제품(K8s 에이전트) 전용.
  # gitops의 overlays/gke/bootstrap/secrets.yaml 과 반드시 일치해야 한다.
  # monitoring 네임스페이스의 SecretSync를 재사용할 수 없는 이유는 그 파일에
  # 적혀 있다 — Secret이 네임스페이스를 못 넘고, Workload Identity 바인딩도
  # (네임스페이스, KSA) 조합이라 그렇다. boa-whatap-host·boa-whatap-port는
  # monitoring과 같은 시크릿을 공유하지만, 이 네임스페이스의 KSA용으로 별도
  # 바인딩이 또 필요하다.
  whatap_monitoring_namespace             = "whatap-monitoring"
  whatap_credentials_sync_service_account = "whatap-credentials-sync"

  whatap_k8s_secret_ids = [
    "boa-whatap-kubernetes-license",
    "boa-whatap-host",
    "boa-whatap-port",
  ]
}


# ===================================================
# observability-secret-sync KSA — whatap 시크릿 읽기
# ===================================================

resource "google_secret_manager_secret_iam_member" "observability_whatap" {
  for_each = toset(local.whatap_secret_ids)

  project   = var.gcp_project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${local.workload_identity_pool}/subject/ns/${local.observability_namespace}/sa/${local.secret_sync_service_account}"
}


# ===================================================
# whatap-credentials-sync KSA (whatap-monitoring 네임스페이스) —
# 와탭 쿠버네티스 제품 자격증명(gitops overlays/gke/bootstrap/secrets.yaml
# 의 SecretProviderClass/SecretSync) 읽기
# ===================================================

resource "google_secret_manager_secret_iam_member" "whatap_monitoring_whatap" {
  for_each = toset(local.whatap_k8s_secret_ids)

  project   = var.gcp_project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${local.workload_identity_pool}/subject/ns/${local.whatap_monitoring_namespace}/sa/${local.whatap_credentials_sync_service_account}"
}


# ===================================================
# otel-collector KSA — Cloud Logging·Managed Prometheus 쓰기
# ===================================================

# collector-gateway.yaml 의 googlecloud(로그) · googlemanagedprometheus(지표)
# exporter 가 쓰는 권한. 노드 SA(gcp-gke의 google_service_account.gke_node)
# 가 이미 이 role들을 갖고 있지만, GKE_METADATA 모드에서는 파드가 노드 SA를
# 못 쓰므로 KSA에 직접 부여해야 한다.
resource "google_project_iam_member" "otel_collector" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.gcp_project_id
  role    = each.value
  member  = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${local.workload_identity_pool}/subject/ns/${local.observability_namespace}/sa/${local.collector_service_account}"
}

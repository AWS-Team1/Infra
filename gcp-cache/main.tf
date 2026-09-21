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

locals {
  valkey_discovery_endpoints = flatten([
    for endpoint in google_memorystore_instance.valkey.endpoints : [
      for connection in endpoint.connections : connection.psc_auto_connection[0]
      if connection.psc_auto_connection[0].connection_type == "CONNECTION_TYPE_DISCOVERY"
    ]
  ])
}

resource "google_project_service" "cache" {
  for_each = toset([
    "memorystore.googleapis.com",
    "networkconnectivity.googleapis.com",
    "serviceconsumermanagement.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_subnetwork" "valkey_psc" {
  name          = "boa-valkey-psc"
  ip_cidr_range = "10.10.48.0/29"
  region        = var.region
  network       = data.terraform_remote_state.gcp_core.outputs.network_id
}

resource "google_network_connectivity_service_connection_policy" "valkey" {
  name          = "boa-valkey"
  location      = var.region
  service_class = "gcp-memorystore"
  network       = data.terraform_remote_state.gcp_core.outputs.network_id

  psc_config {
    subnetworks = [google_compute_subnetwork.valkey_psc.id]
    limit       = 2
  }

  depends_on = [google_project_service.cache]
}

resource "google_memorystore_instance" "valkey" {
  instance_id = "boa-valkey"
  location    = var.region

  shard_count    = 1
  replica_count  = 0
  node_type      = "SHARED_CORE_NANO"
  engine_version = "VALKEY_8_0"
  mode           = "CLUSTER"

  authorization_mode      = "AUTH_DISABLED"
  transit_encryption_mode = "TRANSIT_ENCRYPTION_DISABLED"

  desired_auto_created_endpoints {
    network    = data.terraform_remote_state.gcp_core.outputs.network_id
    project_id = var.gcp_project_id
  }

  zone_distribution_config {
    mode = "SINGLE_ZONE"
    zone = "${var.region}-a"
  }

  deletion_protection_enabled = false

  depends_on = [google_network_connectivity_service_connection_policy.valkey]
}

resource "google_secret_manager_secret" "valkey_host" {
  secret_id = "boa-valkey-host"

  replication {
    auto {}
  }

  depends_on = [google_project_service.cache]
}

resource "google_secret_manager_secret_version" "valkey_host" {
  secret      = google_secret_manager_secret.valkey_host.id
  secret_data = one(local.valkey_discovery_endpoints).ip_address
}

resource "google_secret_manager_secret_iam_member" "gke" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.valkey_host.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${var.gcp_project_id}.svc.id.goog/subject/ns/bank-of-anthos/sa/bank-app-secret-sync"
}

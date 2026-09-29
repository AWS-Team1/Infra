# The GKE Ingress controller owns the load balancer components. Terraform owns
# the stable cross-cloud resources that must survive Ingress recreation.
resource "google_compute_global_address" "argocd" {
  name = "boa-gke-argocd-ip"
}

data "google_dns_managed_zone" "public" {
  name = "bespinglobal-site-prod"
}

resource "google_dns_record_set" "argocd" {
  managed_zone = data.google_dns_managed_zone.public.name
  name         = "argocd-gcp.${data.google_dns_managed_zone.public.dns_name}"
  type         = "A"
  ttl          = 60
  rrdatas      = [google_compute_global_address.argocd.address]
}

import {
  to = google_dns_record_set.argocd
  id = "projects/${var.gcp_project_id}/managedZones/bespinglobal-site-prod/rrsets/argocd-gcp.bespinglobal.site./A"
}

# The GKE Ingress controller owns the load balancer components. Terraform owns
# the stable cross-cloud resources that must survive Ingress recreation.
resource "google_compute_global_address" "argocd" {
  name = "boa-gke-argocd-ip"
}

data "aws_route53_zone" "public" {
  name         = "bespinglobal.site."
  private_zone = false
}

resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "argocd-gcp.bespinglobal.site"
  type    = "A"
  ttl     = 60
  records = [google_compute_global_address.argocd.address]
}

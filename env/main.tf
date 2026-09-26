# Shared, non-sensitive development environment contract.
# Every Terraform root consumes this local module, so GitHub Actions and
# an interactive Code Server run use exactly the same defaults.
locals {
  project_name                     = "boa"
  aws_region                       = "ap-northeast-2"
  state_bucket                     = "boa-terraform-state-6416"
  cluster_name                     = "boa-eks"
  private_zone_name                = "boa.internal"
  public_zone_name                 = "bespinglobal.site"
  certificate_domain               = "*.bespinglobal.site"
  argocd_host                      = "argocd.bespinglobal.site"
  grafana_host                     = "grafana.bespinglobal.site"
  eks_baseline_public_access_cidrs = ["15.165.176.99/32"]
}

output "project_name" { value = local.project_name }
output "aws_region" { value = local.aws_region }
output "state_bucket" { value = local.state_bucket }
output "cluster_name" { value = local.cluster_name }
output "private_zone_name" { value = local.private_zone_name }
output "public_zone_name" { value = local.public_zone_name }
output "certificate_domain" { value = local.certificate_domain }
output "argocd_host" { value = local.argocd_host }
output "grafana_host" { value = local.grafana_host }
output "eks_baseline_public_access_cidrs" { value = local.eks_baseline_public_access_cidrs }

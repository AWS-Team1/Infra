# ---------------------------------------------------------
# ops ALB
# ---------------------------------------------------------

# argocd_host는 HTTPS 리스너 Host 조건과 Route53 A(alias) 이름에 함께 사용한다.
output "ops_alb_dns_name" {
  value = module.ops_alb.alb_dns_name
}

output "ops_alb_zone_id" {
  value = module.ops_alb.alb_zone_id
}


# 관측성 대상 그룹을 붙일 때 쓸 리스너 ARN.
output "ops_alb_https_listener_arn" {
  value = module.ops_alb.https_listener_arn
}

output "ops_alb_security_group_id" {
  value = module.ops_alb.alb_security_group_id
}

output "argocd_target_group_arn" {
  value = module.ops_alb.argocd_target_group_arn
}

output "argocd_url" {
  value = "https://${aws_route53_record.argocd.fqdn}"
}
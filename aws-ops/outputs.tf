# gitops 의 scripts/bootstrap-eks.sh 가 필수로 읽는 값이다.
# 호스트만 있어야 하며 리포지터리 경로가 붙으면 정규식 검사에서 떨어진다.
output "ecr_registry" {
  value = module.ecr.registry_url
}

# 서비스명 -> 전체 이미지 경로.
# gitops 의 k8s/overlays/dev/aws/kustomization.yaml 의 newName 에 들어간다.
output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ecr_repository_names" {
  value = module.ecr.repository_names
}

output "ecr_repository_arns" {
  value = module.ecr.repository_arns
}

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
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

# 레지스트리 호스트. gitops 의 bootstrap-eks.sh 가 ecr_registry 로 기대하는 값이다.
output "registry_url" {
  value = local.registry_url
}

# 서비스명 -> 전체 이미지 경로. kustomization 의 newName 에 들어갈 값이다.
output "repository_urls" {
  value = {
    for k, v in aws_ecr_repository.this : k => v.repository_url
  }
}

output "repository_names" {
  value = {
    for k, v in aws_ecr_repository.this : k => v.name
  }
}

output "repository_arns" {
  value = {
    for k, v in aws_ecr_repository.this : k => v.arn
  }
}

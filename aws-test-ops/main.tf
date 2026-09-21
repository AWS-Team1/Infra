module "ecr" {
  source = "../aws-modules/ecr"

  project_name = "boa-test"
  region       = "ap-northeast-2"

  repository_names = [
    "frontend",
    "userservice",
    "contacts",
    "balancereader",
    "ledgerwriter",
    "transactionhistory"
  ]

  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  keep_image_count     = 10
}

output "ecr_registry" {
  value = module.ecr.registry_url
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

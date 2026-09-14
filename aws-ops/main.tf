# =========================================================
# ECR
# - 의존하는 루트가 없다. aws-core 없이도 단독으로 apply 된다
# - 리포지터리 이름은 boa-<서비스명> 이다.
#   접두사 없는 기존 6개(frontend, userservice, ...)는 손으로 만든 것이라
#   이 스택이 소유하지 않는다
# =========================================================

module "ecr" {
  source = "../aws-modules/ecr"

  project_name = "boa"
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

provider "aws" {
  region = "ap-northeast-2"

  # 태그 가능한 모든 리소스에 자동으로 붙는다.
  # Name 은 리소스마다 달라야 하므로 여기 두지 않는다.
  default_tags {
    tags = {
      Project   = "boa"
      Component = "observability"
      ManagedBy = "terraform"
      Repo      = "AWS-TEAM1/Infra"
    }
  }
}

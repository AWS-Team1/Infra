provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project   = "boa"
      Component = "dms"
      ManagedBy = "terraform"
      Repo      = "AWS-TEAM1-DEV/Infra"
    }
  }
}

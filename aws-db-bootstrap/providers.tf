provider "aws" {
  # HARD-CODED: 배포 대상 리전에 맞게 변경한다.
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project   = "boa"
      Component = "db-bootstrap"
      ManagedBy = "terraform"
      Repo      = "AWS-TEAM1-DEV/Infra"
    }
  }
}

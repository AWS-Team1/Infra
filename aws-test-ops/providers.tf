provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "boa-test"
      Component   = "ops"
      Environment = "test"
      ManagedBy   = "terraform"
      Repo        = "AWS-TEAM1-DEV/Infra"
    }
  }
}

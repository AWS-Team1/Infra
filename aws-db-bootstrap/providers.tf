provider "aws" {
  region = module.environment.aws_region

  default_tags {
    tags = {
      Project   = module.environment.project_name
      Component = "db-bootstrap"
      ManagedBy = "terraform"
      Repo      = "AWS-TEAM1-DEV/Infra"
    }
  }
}

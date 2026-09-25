provider "aws" {
  region = module.environment.aws_region

  default_tags {
    tags = {
      Project   = module.environment.project_name
      Component = "persistent"
      ManagedBy = "terraform"
      Repo      = "AWS-TEAM1-DEV/Infra"
    }
  }
}

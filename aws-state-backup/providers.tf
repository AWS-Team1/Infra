provider "aws" {
  region = local.backup_region

  default_tags {
    tags = {
      Project   = module.environment.project_name
      Component = "terraform-state-backup"
      ManagedBy = "terraform"
      Repo      = "AWS-TEAM1-DEV/Infra"
    }
  }
}

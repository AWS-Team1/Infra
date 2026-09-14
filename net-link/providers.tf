provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project   = "boa"
      Component = "net-link"
      ManagedBy = "terraform"
      Repo      = "AWS-TEAM1-DEV/Infra"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

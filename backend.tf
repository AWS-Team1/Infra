terraform {
  backend "s3" {
    bucket  = "final-project-s3-team1"
    key     = "project/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

provider "google" {
  project = var.gcp_project_id
  region  = "asia-northeast2"
}

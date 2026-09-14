provider "google" {
  project = var.gcp_project_id
  region  = var.region

  # AWS 의 default_tags 에 대응한다. GCP 는 태그가 아니라 라벨이고
  # 리소스마다 지원 여부가 달라 provider 수준 기본값이 없다.
  # 각 모듈에서 user_labels / labels 로 붙인다.
}

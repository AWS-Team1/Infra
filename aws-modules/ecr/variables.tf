variable "project_name" {
  description = "리포지터리 이름 접두사. 최종 이름은 <project_name>-<서비스명> 이 된다"
  type        = string
}

variable "region" {
  description = "레지스트리 호스트 조립에 쓴다"
  type        = string
}

variable "repository_names" {
  description = "만들 리포지터리의 서비스명 목록. 접두사는 project_name 이 붙는다"
  type        = list(string)
}

# 같은 태그로 다시 푸시하는 것을 막는다. CI 가 커밋 SHA 로 태깅하는 전제다.
variable "image_tag_mutability" {
  description = "MUTABLE 또는 IMMUTABLE"
  type        = string
  default     = "IMMUTABLE"
}

# ECR 기본 스캔은 무료다. 푸시할 때마다 CVE 를 훑는다.
variable "scan_on_push" {
  description = "푸시 시 취약점 스캔 여부"
  type        = bool
  default     = true
}

variable "keep_image_count" {
  description = "리포지터리당 보관할 이미지 개수. 초과분은 오래된 것부터 만료"
  type        = number
  default     = 10
}

# true 면 이미지가 남아 있어도 terraform destroy 가 리포지터리를 지운다.
# 기본은 false — 실수로 이미지를 날리지 않게 한다.
variable "force_delete" {
  description = "이미지가 있어도 삭제를 허용할지"
  type        = bool
  default     = false
}

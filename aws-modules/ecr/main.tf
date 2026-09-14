# ===================================================
# ECR PRIVATE REPOSITORY
# ===================================================
# aws_ecr_repository 는 프라이빗 레지스트리 전용이다. 공개 여부 설정이 없다.
# 퍼블릭이 필요하면 aws_ecrpublic_repository 를 us-east-1 에 따로 만들어야 한다.

# 레지스트리 호스트(<계정ID>.dkr.ecr.<리전>.amazonaws.com) 조립에 쓴다.
data "aws_caller_identity" "current" {}

locals {
  # bootstrap-eks.sh 가 정규식으로 검사하는 형태다 — 호스트만, 리포지터리 경로 없음.
  #   ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com$
  registry_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

# 서비스마다 프라이빗 리포지터리 하나. CI 가 이미지를 푸시하고
# gitops 의 kustomization.yaml newName 이 이 주소를 가리킨다.
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.project_name}-${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = "${var.project_name}-${each.value}"
    Service = each.value
  }
}


# ===================================================
# LIFECYCLE POLICY
# ===================================================
# 규칙 순서에 제약이 있다. tagStatus = "any" 규칙은 rulePriority 가
# 가장 커야 하므로 반드시 마지막에 둔다.

# 리포지터리마다 수명주기 정책을 붙인다. 오래된 이미지가 무한히 쌓이는 것을 막는다.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"

        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }

        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep the latest ${var.keep_image_count} images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_image_count
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}

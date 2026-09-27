# Observability archive survives the routine AWS teardown. It is removed only
# by the explicitly confirmed full_teardown path.
#
# 와탭·Grafana 계정은 콘솔에서 만든 진짜 콘솔 전용 시크릿을 그대로 쓰기로
# 팀이 확정했다(2026-09-27, ECR과 같은 패턴 — AGENTS.md 규칙 4). 이전에는
# 여기서 aws_secretsmanager_secret.observability_whatap/.observability_grafana
# 컨테이너를 만들었지만, 이미 apply되어 실제 값이 채워진 콘솔 시크릿과 별개로
# Terraform이 같은 이름을 다시 선언하면 안 된다. 코드 삭제 전에 반드시
# `terraform state rm aws_secretsmanager_secret.observability_whatap` ·
# `... .observability_grafana` 로 state에서만 먼저 떼어내야 한다 — 순서를
# 반대로 하면 다음 apply가 이미 값이 채워진 실제 시크릿을 destroy한다.
data "aws_caller_identity" "current" {}

locals {
  telemetry_bucket_name = "${module.environment.project_name}-telemetry-archive-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "telemetry" {
  bucket = local.telemetry_bucket_name

  # Routine destroy does not include persistent. When full_teardown is explicitly
  # requested, remove all archive objects and versions so the teardown can finish.
  force_destroy = true

  tags = {
    Name = local.telemetry_bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "telemetry" {
  bucket = aws_s3_bucket.telemetry.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "telemetry" {
  bucket = aws_s3_bucket.telemetry.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "telemetry" {
  bucket = aws_s3_bucket.telemetry.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "telemetry" {
  bucket = aws_s3_bucket.telemetry.id

  rule {
    id     = "tier-and-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "telemetry" {
  bucket = aws_s3_bucket.telemetry.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"

        Resource = [
          aws_s3_bucket.telemetry.arn,
          "${aws_s3_bucket.telemetry.arn}/*",
        ]

        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Observability archive and secret containers survive the routine AWS teardown.
# They are removed only by the explicitly confirmed full_teardown path.
data "aws_caller_identity" "current" {}

locals {
  telemetry_bucket_name = "${module.environment.project_name}-telemetry-archive-${data.aws_caller_identity.current.account_id}"
}

resource "aws_secretsmanager_secret" "observability_whatap" {
  name        = "/${module.environment.project_name}/observability/whatap"
  description = "WhaTap license keys. Values are set out-of-band, never by Terraform."

  recovery_window_in_days = 0

  tags = {
    Name = "${module.environment.project_name}-observability-whatap"
  }
}

resource "aws_secretsmanager_secret" "observability_grafana" {
  name        = "/${module.environment.project_name}/observability/grafana"
  description = "Grafana admin credentials. Values are set out-of-band, never by Terraform."

  recovery_window_in_days = 0

  tags = {
    Name = "${module.environment.project_name}-observability-grafana"
  }
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

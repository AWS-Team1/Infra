locals {
  backup_region               = "ap-northeast-1"
  backup_object_prefix        = "terraform-state-backups"
  github_terraform_role_name  = "boa-github-terraform-dev"
  terraform_state_bucket_name = "${module.environment.project_name}-terraform-state-backup-${data.aws_caller_identity.current.account_id}-${local.backup_region}"
}

data "aws_caller_identity" "current" {}

# The role is owned outside this repository. This root only references it as a
# bucket-policy principal and does not create, replace, or attach IAM policies.
data "aws_iam_role" "github_terraform" {
  name = local.github_terraform_role_name
}

resource "aws_s3_bucket" "terraform_state_backup" {
  bucket        = local.terraform_state_bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = local.terraform_state_bucket_name
    Purpose = "terraform-state-dr-backup"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_backup" {
  bucket = aws_s3_bucket.terraform_state_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "terraform_state_backup" {
  bucket = aws_s3_bucket.terraform_state_backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state_backup" {
  bucket = aws_s3_bucket.terraform_state_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_backup" {
  bucket = aws_s3_bucket.terraform_state_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "terraform_state_backup" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.terraform_state_backup.arn,
      "${aws_s3_bucket.terraform_state_backup.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowGitHubTerraformBucketLocation"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_role.github_terraform.arn]
    }

    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.terraform_state_backup.arn]
  }

  statement {
    sid    = "AllowGitHubTerraformBackupObjects"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_role.github_terraform.arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.terraform_state_backup.arn}/${local.backup_object_prefix}/*"]
  }

  statement {
    sid    = "DenyGitHubTerraformBackupObjectDeletion"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_role.github_terraform.arn]
    }

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]
    resources = ["${aws_s3_bucket.terraform_state_backup.arn}/${local.backup_object_prefix}/*"]
  }
}

resource "aws_s3_bucket_policy" "terraform_state_backup" {
  bucket = aws_s3_bucket.terraform_state_backup.id
  policy = data.aws_iam_policy_document.terraform_state_backup.json

  depends_on = [aws_s3_bucket_public_access_block.terraform_state_backup]
}

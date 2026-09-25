variable "console_user_group_name" {
  description = "IAM group whose users can view EKS resources"
  type        = string
  default     = "admin-group"
}

variable "github_terraform_role_arn" {
  description = "IAM Role ARN assumed by GitHub Actions for Terraform"
  type        = string
  default     = "arn:aws:iam::769413326616:role/boa-github-terraform-dev"
}

variable "code_server_role_arn" {
  description = "IAM Role used by the interactive Code Server Terraform operator"
  type        = string
  default     = "arn:aws:iam::769413326616:role/CodeServerEc2Role"
}

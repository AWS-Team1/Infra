variable "code_server_role_arn" {
  description = "IAM Role ARN used by Code Server for EKS access"
  type        = string
  default     = "arn:aws:iam::769413326616:role/CodeServerEc2Role"
}

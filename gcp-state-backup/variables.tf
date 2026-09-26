variable "gcp_project_id" {
  description = "GCP project that owns the cross-cloud Terraform state backup bucket."
  type        = string
  default     = "kdt4-1-506106"
}

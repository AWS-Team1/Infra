variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_access_cidrs" {
  type = list(string)
}

variable "node_group_name" {
  type = string
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_capacity_type" {
  type = string
}

variable "node_disk_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_desired_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "node_max_unavailable" {
  type = number
}

variable "control_plane_log_retention_days" {
  type = number
}

variable "cluster_admin_role_arns" {
  description = "IAM role ARNs that receive EKS cluster admin access"
  type        = list(string)
}

variable "region" {
  description = "AWS Region"
  type        = string
}

# Secrets Manager 경로 접두사 등 클러스터명과 별개로 쓰이는 이름 접두사
variable "project_name" {
  description = "리소스 이름 / Secrets Manager 경로 접두사"
  type        = string
}

# eks-iam 모듈이 만든 역할 ARN 을 받는다.
variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "karpenter_role_arn" {
  type = string
}

variable "ebs_csi_role_arn" {
  type = string
}

variable "bank_of_anthos_role_arn" {
  type = string
}

variable "console_user_group_name" {
  description = "IAM group whose users can view EKS resources"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Namespace for AWS Load Balancer Controller"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "ServiceAccount name for AWS Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "cluster_name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }

variable "namespace" {
  type    = string
  default = "kube-system"
}

variable "service_account_name" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "chart_version" {
  type    = string
  default = "3.5.0"
}

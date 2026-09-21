variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for karpenter.sh/discovery tag"
  type        = string
}

variable "vpc_cidr" {
  description = "boa-vpc IPv4 CIDR"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "availability_zones" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "db_subnet_cidrs" {
  type = list(string)
}

variable "cache_subnet_cidrs" {
  type = list(string)
}

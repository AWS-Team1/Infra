output "alb_sg_id" {
  value = aws_security_group.alb.id
}

# output "eks_sg_id" {
#   value = aws_security_group.eks.id
# }

output "db_sg_id" {
  value = aws_security_group.db.id
}

# ElastiCache에 연결할 Security Group ID
output "cache_sg_id" {
  value = aws_security_group.cache.id
}

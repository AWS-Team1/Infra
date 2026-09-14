# IAM Role for RDS Enhanced Monitoring
# 향상된 모니터링이 맡는 역할. aws_db_instance 의 monitoring_role_arn 으로 들어간다.
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-rds-monitoring-role"
  }
}


# AWS Managed Policy for RDS Enhanced Monitoring
# OS 지표를 CloudWatch 로 보낼 권한(AWS 관리형).
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

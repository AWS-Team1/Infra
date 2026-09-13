# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}


# PostgreSQL Custom Parameter Group
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-postgres16"
  family = "postgres16"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "${var.project_name}-postgres16"
  }
}


# PostgreSQL RDS
resource "aws_db_instance" "main" {
  identifier = var.db_identifier

  # Database
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username
  port     = 5432

  # Master password is generated and managed by AWS Secrets Manager
  manage_master_user_password = true

  # Storage
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.db_security_group_id]
  publicly_accessible    = false
  multi_az               = true

  # Parameter Group
  parameter_group_name = aws_db_parameter_group.main.name

  # Backup
  backup_retention_period  = var.backup_retention_period
  delete_automated_backups = true
  skip_final_snapshot      = true
  copy_tags_to_snapshot    = true

  # Version / Apply
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Logs
  enabled_cloudwatch_logs_exports = [
    "postgresql"
  ]


  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period

  # Enhanced Monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Deletion Protection
  deletion_protection = false

  tags = {
    Name = var.db_identifier
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_monitoring,
    aws_cloudwatch_log_group.rds_os_metrics
  ]
}

resource "aws_cloudwatch_log_group" "rds_os_metrics" {
  count = var.create_os_metrics_log_group ? 1 : 0

  name              = "RDSOSMetrics"
  retention_in_days = var.enhanced_monitoring_log_retention_days

  tags = {
    Name = "RDSOSMetrics"
  }
}

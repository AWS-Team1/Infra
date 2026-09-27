# =========================================================
# aws-infra-observability
#
# EKS 내부 관측을 소유하는 aws-observability와 분리된 root다. RDS, ALB,
# NAT Gateway, Site-to-Site VPN, DMS, ElastiCache, S3의 CSP native dashboard만
# 소유한다.
#
# 개별 resource ID를 remote state로 연결하지 않고 CloudWatch SEARCH 표현식으로
# 최근 2주 안에 지표를 발행한 리소스를 자동 발견한다. 리소스를 재생성해 ID가
# 바뀌어도 dashboard 코드를 수정하지 않아도 된다.
# =========================================================

locals {
  dashboard_metrics = [
    # RDS
    { title = "RDS - CPU utilization", namespace = "AWS/RDS", metric_name = "CPUUtilization", statistic = "Average", period = 300 },
    { title = "RDS - Freeable memory", namespace = "AWS/RDS", metric_name = "FreeableMemory", statistic = "Average", period = 300 },
    { title = "RDS - Free storage space", namespace = "AWS/RDS", metric_name = "FreeStorageSpace", statistic = "Average", period = 300 },
    { title = "RDS - Database connections", namespace = "AWS/RDS", metric_name = "DatabaseConnections", statistic = "Average", period = 300 },
    { title = "RDS - Read latency", namespace = "AWS/RDS", metric_name = "ReadLatency", statistic = "Average", period = 300 },
    { title = "RDS - Write latency", namespace = "AWS/RDS", metric_name = "WriteLatency", statistic = "Average", period = 300 },

    # Application Load Balancer
    { title = "ALB - Request count", namespace = "AWS/ApplicationELB", metric_name = "RequestCount", statistic = "Sum", period = 300 },
    { title = "ALB - Target response time", namespace = "AWS/ApplicationELB", metric_name = "TargetResponseTime", statistic = "Average", period = 300 },
    { title = "ALB - Target 5XX", namespace = "AWS/ApplicationELB", metric_name = "HTTPCode_Target_5XX_Count", statistic = "Sum", period = 300 },
    { title = "ALB - Unhealthy targets", namespace = "AWS/ApplicationELB", metric_name = "UnHealthyHostCount", statistic = "Maximum", period = 300 },

    # NAT Gateway
    { title = "NAT - Port allocation errors", namespace = "AWS/NATGateway", metric_name = "ErrorPortAllocation", statistic = "Sum", period = 300 },
    { title = "NAT - Dropped packets", namespace = "AWS/NATGateway", metric_name = "PacketsDropCount", statistic = "Sum", period = 300 },
    { title = "NAT - Active connections", namespace = "AWS/NATGateway", metric_name = "ActiveConnectionCount", statistic = "Maximum", period = 300 },

    # Site-to-Site VPN
    { title = "VPN - Tunnel state", namespace = "AWS/VPN", metric_name = "TunnelState", statistic = "Minimum", period = 300 },
    { title = "VPN - Data in", namespace = "AWS/VPN", metric_name = "TunnelDataIn", statistic = "Sum", period = 300 },
    { title = "VPN - Data out", namespace = "AWS/VPN", metric_name = "TunnelDataOut", statistic = "Sum", period = 300 },

    # Database Migration Service
    { title = "DMS - CDC source latency", namespace = "AWS/DMS", metric_name = "CDCLatencySource", statistic = "Maximum", period = 300 },
    { title = "DMS - CDC target latency", namespace = "AWS/DMS", metric_name = "CDCLatencyTarget", statistic = "Maximum", period = 300 },
    { title = "DMS - CPU utilization", namespace = "AWS/DMS", metric_name = "CPUUtilization", statistic = "Average", period = 300 },
    { title = "DMS - Freeable memory", namespace = "AWS/DMS", metric_name = "FreeableMemory", statistic = "Average", period = 300 },

    # ElastiCache Serverless
    { title = "ElastiCache - Processing units", namespace = "AWS/ElastiCache", metric_name = "ElastiCacheProcessingUnits", statistic = "Sum", period = 300 },
    { title = "ElastiCache - Cache hit rate", namespace = "AWS/ElastiCache", metric_name = "CacheHitRate", statistic = "Average", period = 300 },
    { title = "ElastiCache - Current connections", namespace = "AWS/ElastiCache", metric_name = "CurrConnections", statistic = "Average", period = 300 },
    { title = "ElastiCache - Throttled commands", namespace = "AWS/ElastiCache", metric_name = "ThrottledCmds", statistic = "Sum", period = 300 },

    # S3 storage metrics are published daily. Request metrics are intentionally
    # omitted because they require an opt-in metrics configuration per bucket.
    { title = "S3 - Bucket size", namespace = "AWS/S3", metric_name = "BucketSizeBytes", statistic = "Average", period = 86400 },
    { title = "S3 - Object count", namespace = "AWS/S3", metric_name = "NumberOfObjects", statistic = "Average", period = 86400 },
  ]

  dashboard_widgets = concat(
    [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# AWS Infrastructure Overview\nEKS 내부 지표를 제외한 AWS 관리형 리소스입니다. 리소스 ID는 CloudWatch SEARCH로 자동 발견합니다."
        }
      }
    ],
    [
      for index, metric in local.dashboard_metrics : {
        type   = "metric"
        x      = (index % 2) * 12
        y      = 2 + floor(index / 2) * 6
        width  = 12
        height = 6
        properties = {
          title   = metric.title
          view    = "timeSeries"
          stacked = false
          region  = module.environment.aws_region
          period  = metric.period
          metrics = [
            [
              {
                expression = format(
                  "SEARCH('{%s} MetricName=\"%s\"', '%s', %d)",
                  metric.namespace,
                  metric.metric_name,
                  metric.statistic,
                  metric.period,
                )
                id     = "q${index}"
                region = module.environment.aws_region
              }
            ]
          ]
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ],
  )
}

resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = var.dashboard_name
  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}

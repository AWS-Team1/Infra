# =========================================================
# gcp-infra-observability
#
# GKE 내부 관측을 소유하는 gcp-observability와 분리된 root다. Cloud SQL,
# external Application Load Balancer, HA VPN, Cloud NAT, Cloud Storage의
# CSP native dashboard만 소유한다.
#
# 특정 resource ID나 다른 Terraform state를 참조하지 않는다. Monitoring
# filter가 프로젝트 안의 현재 time series를 선택하므로 리소스 재생성에도
# dashboard 정의는 유지된다.
# =========================================================

locals {
  dashboard_charts = [
    # Cloud SQL for PostgreSQL
    { title = "Cloud SQL - CPU utilization", metric_type = "cloudsql.googleapis.com/database/cpu/utilization", resource_type = "cloudsql_database", aligner = "ALIGN_MEAN", alignment_period = "60s" },
    { title = "Cloud SQL - Memory utilization", metric_type = "cloudsql.googleapis.com/database/memory/utilization", resource_type = "cloudsql_database", aligner = "ALIGN_MEAN", alignment_period = "60s" },
    { title = "Cloud SQL - Disk utilization", metric_type = "cloudsql.googleapis.com/database/disk/utilization", resource_type = "cloudsql_database", aligner = "ALIGN_MEAN", alignment_period = "60s" },
    { title = "Cloud SQL - PostgreSQL connections", metric_type = "cloudsql.googleapis.com/database/postgresql/num_backends", resource_type = "cloudsql_database", aligner = "ALIGN_MEAN", alignment_period = "60s" },
    { title = "Cloud SQL - Read operations/sec", metric_type = "cloudsql.googleapis.com/database/disk/read_ops_count", resource_type = "cloudsql_database", aligner = "ALIGN_RATE", alignment_period = "60s" },
    { title = "Cloud SQL - Write operations/sec", metric_type = "cloudsql.googleapis.com/database/disk/write_ops_count", resource_type = "cloudsql_database", aligner = "ALIGN_RATE", alignment_period = "60s" },
    { title = "Cloud SQL - Network received bytes/sec", metric_type = "cloudsql.googleapis.com/database/network/received_bytes_count", resource_type = "cloudsql_database", aligner = "ALIGN_RATE", alignment_period = "60s" },
    { title = "Cloud SQL - Network sent bytes/sec", metric_type = "cloudsql.googleapis.com/database/network/sent_bytes_count", resource_type = "cloudsql_database", aligner = "ALIGN_RATE", alignment_period = "60s" },

    # Global external Application Load Balancer
    { title = "Load Balancer - Requests/sec", metric_type = "loadbalancing.googleapis.com/https/request_count", resource_type = "https_lb_rule", aligner = "ALIGN_RATE", alignment_period = "60s" },
    { title = "Load Balancer - P95 total latency", metric_type = "loadbalancing.googleapis.com/https/total_latencies", resource_type = "https_lb_rule", aligner = "ALIGN_PERCENTILE_95", alignment_period = "60s" },
    { title = "Load Balancer - 5XX responses/sec", metric_type = "loadbalancing.googleapis.com/https/request_count", resource_type = "https_lb_rule", aligner = "ALIGN_RATE", alignment_period = "60s", filter = "metric.label.\"response_code_class\"=\"500\"" },

    # HA VPN
    { title = "VPN - Tunnel established", metric_type = "vpn.googleapis.com/tunnel_established", resource_type = "vpn_gateway", aligner = "ALIGN_MIN", alignment_period = "60s" },
    { title = "VPN - Received bytes/sec", metric_type = "vpn.googleapis.com/network/received_bytes_count", resource_type = "vpn_gateway", aligner = "ALIGN_RATE", alignment_period = "60s" },
    { title = "VPN - Sent bytes/sec", metric_type = "vpn.googleapis.com/network/sent_bytes_count", resource_type = "vpn_gateway", aligner = "ALIGN_RATE", alignment_period = "60s" },

    # Cloud NAT
    { title = "Cloud NAT - Port usage", metric_type = "router.googleapis.com/nat/port_usage", resource_type = "nat_gateway", aligner = "ALIGN_MAX", alignment_period = "60s" },
    { title = "Cloud NAT - Allocation failures", metric_type = "router.googleapis.com/nat/nat_allocation_failed", resource_type = "nat_gateway", aligner = "ALIGN_COUNT_TRUE", alignment_period = "60s" },
    { title = "Cloud NAT - New connections/sec", metric_type = "router.googleapis.com/nat/new_connections_count", resource_type = "nat_gateway", aligner = "ALIGN_RATE", alignment_period = "60s" },
    { title = "Cloud NAT - Dropped packets/sec", metric_type = "router.googleapis.com/nat/dropped_sent_packets_count", resource_type = "nat_gateway", aligner = "ALIGN_RATE", alignment_period = "60s" },

    # Cloud Storage daily project metrics
    { title = "Cloud Storage - Total bytes", metric_type = "storage.googleapis.com/storage/v2/total_bytes", resource_type = "gcs_bucket", aligner = "ALIGN_MEAN", alignment_period = "300s" },
    { title = "Cloud Storage - Object count", metric_type = "storage.googleapis.com/storage/v2/total_count", resource_type = "gcs_bucket", aligner = "ALIGN_MEAN", alignment_period = "300s" },
  ]

  dashboard_widgets = concat(
    [
      {
        text = {
          content = "# GCP Infrastructure Overview\nGKE 내부 지표를 제외한 GCP 관리형 리소스입니다. 프로젝트의 현재 time series를 자동으로 조회합니다."
          format  = "MARKDOWN"
        }
      }
    ],
    [
      for chart in local.dashboard_charts : {
        title = chart.title
        xyChart = {
          dataSets = [
            {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = join(" AND ", compact([
                    "metric.type=\"${chart.metric_type}\"",
                    "resource.type=\"${chart.resource_type}\"",
                    try(chart.filter, ""),
                  ]))
                  aggregation = {
                    alignmentPeriod  = chart.alignment_period
                    perSeriesAligner = chart.aligner
                  }
                }
              }
              plotType = "LINE"
            }
          ]
          timeshiftDuration = "0s"
          yAxis = {
            label = ""
            scale = "LINEAR"
          }
        }
      }
    ],
  )
}

resource "google_monitoring_dashboard" "infrastructure" {
  project = var.gcp_project_id

  dashboard_json = jsonencode({
    displayName = var.dashboard_display_name
    gridLayout = {
      columns = "2"
      widgets = local.dashboard_widgets
    }
  })
}

# =========================================================
# aws-modules/observability
#
# 관측 2층 구조 중 "AWS 가 관리하는 것은 AWS 가 본다" 쪽의 AWS 측 리소스다.
# 클러스터 안에 올라가는 것(수집기·계측·Grafana 파드)은 gitops 가 담당하고,
# 이 모듈은 그것들이 필요로 하는 AWS 쪽 수신구와 권한만 만든다.
#
# 만드는 것
#   - 로그 그룹 3개 (앱 로그 / 수집기 지표 EMF / 마스킹 감사 기록)
#   - 로그 그룹의 데이터 보호 정책 (민감정보 마스킹)
#   - persistent root가 소유하는 텔레메트리 S3 버킷에 대한 쓰기 권한
#   - 수집기·Grafana 의 Pod Identity 역할 (iam.tf)
#   - Grafana 를 ops ALB 에 붙이는 대상 그룹·리스너 규칙 (alb.tf)
#
# 만들지 않는 것
#   - amazon-cloudwatch-observability 애드온. 오픈텔레메트리 자동계측 웹훅과
#     충돌하므로 설계 단계에서 배제했다 (autoMonitor.monitorAllServices 기본 true)
#   - Route53 레코드. aws-ops 가 argocd 레코드를 갖고 있듯 루트가 만든다
# =========================================================

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # 클러스터 리소스를 참조하지 않고 조립한다. eks-iam 모듈과 같은 방식이다.
  cluster_arn = "arn:${local.partition}:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"

  # 수집기가 쓰는 로그 그룹 이름. gitops 의 수집기 설정과 반드시 일치해야 한다.
  application_log_group_name = "/aws/eks/${var.cluster_name}/application"
  emf_log_group_name         = "/aws/eks/${var.cluster_name}/otel-emf"
  audit_log_group_name       = "/aws/logs-data-protection/${var.cluster_name}"

  telemetry_bucket_name = "${var.project_name}-telemetry-archive-${local.account_id}"
}


# ===================================================
# LOG GROUPS
# ===================================================

# 앱 로그가 들어오는 곳. 수집기의 awscloudwatchlogs exporter 가 여기에 쓴다.
# EKS 컨트롤 플레인 로그 그룹(/aws/eks/<cluster>/cluster)과는 별개다 — 그쪽은
# aws-modules/eks 가 만들고 AWS 가 직접 쓴다.
resource "aws_cloudwatch_log_group" "application" {
  name              = local.application_log_group_name
  retention_in_days = var.application_log_retention_days

  tags = {
    Name = "${var.cluster_name}-application-logs"
  }
}

# 수집기가 awsemf exporter 로 내보내는 지표가 로그 이벤트 형태로 들어오는 곳.
# CloudWatch 가 여기서 사용자 지정 지표를 추출한다.
resource "aws_cloudwatch_log_group" "emf" {
  name              = local.emf_log_group_name
  retention_in_days = var.application_log_retention_days

  tags = {
    Name = "${var.cluster_name}-otel-emf"
  }
}

# 데이터 보호 정책이 "무엇을 마스킹했는지"를 남기는 곳.
# 마스킹된 값 자체는 남지 않는다 — 어느 로그 그룹의 어느 식별자가 몇 건 걸렸는지만 남는다.
# 감사 증적이므로 앱 로그보다 길게 보존한다.
resource "aws_cloudwatch_log_group" "data_protection_audit" {
  name              = local.audit_log_group_name
  retention_in_days = var.audit_findings_retention_days

  tags = {
    Name = "${var.cluster_name}-data-protection-findings"
  }
}


# ===================================================
# DATA PROTECTION POLICY — 민감정보 마스킹
# ===================================================

# 데이터 보호 정책은 로그를 수집할 때 민감 데이터를 탐지하고 기본 조회에서
# 마스킹한다. 저장된 원본은 보존되며 logs:Unmask 권한이 있는 주체만 볼 수 있다.
#
# 즉 이것은 "저장 안 함"이 아니라 "기본적으로 안 보임"이다. 그래서
# outputs.tf 가 내보내는 unmask 정책은 어디에도 부착하지 않는다 —
# 감사 시 사람이 의도적으로 붙이는 것이 통제 지점이다.
#
# Statement 순서가 의미를 갖는다. Audit 가 먼저 와야 무엇이 걸렸는지 기록된다.
locals {
  data_identifier_arns = concat(
    var.managed_data_identifiers,
    [for name, _ in var.custom_data_identifiers : name],
  )

  data_protection_policy = {
    Name    = "${var.cluster_name}-sensitive-data-policy"
    Version = "2021-06-01"

    Configuration = {
      CustomDataIdentifier = [
        for name, regex in var.custom_data_identifiers : {
          Name  = name
          Regex = regex
        }
      ]
    }

    Statement = [
      {
        Sid            = "AuditFindings"
        DataIdentifier = local.data_identifier_arns

        Operation = {
          Audit = {
            FindingsDestination = {
              CloudWatchLogs = {
                LogGroup = aws_cloudwatch_log_group.data_protection_audit.name
              }
            }
          }
        }
      },
      {
        Sid            = "MaskOnRead"
        DataIdentifier = local.data_identifier_arns

        Operation = {
          Deidentify = {
            MaskConfig = {}
          }
        }
      },
    ]
  }
}

resource "aws_cloudwatch_log_data_protection_policy" "application" {
  count = var.enable_log_data_protection ? 1 : 0

  log_group_name  = aws_cloudwatch_log_group.application.name
  policy_document = jsonencode(local.data_protection_policy)
}

# 앱 지표에는 계좌번호가 들어가지 않지만, 차원(dimension) 이름을 잘못 잡으면
# 들어갈 수 있다. 같은 정책을 EMF 로그 그룹에도 건다.
resource "aws_cloudwatch_log_data_protection_policy" "emf" {
  count = var.enable_log_data_protection ? 1 : 0

  log_group_name  = aws_cloudwatch_log_group.emf.name
  policy_document = jsonencode(local.data_protection_policy)
}

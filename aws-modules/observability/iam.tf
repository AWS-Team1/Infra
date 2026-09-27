# ===================================================
# OTEL COLLECTOR — EKS Pod Identity
# ===================================================

# 이 클러스터는 IRSA(OIDC 공급자)를 쓰지 않는다. eks-iam 모듈의 karpenter·ebs-csi
# 역할과 같이 신뢰 주체를 pods.eks.amazonaws.com 으로 둔다.
resource "aws_iam_role" "collector" {
  name = "${var.cluster_name}-otel-collector-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "pods.eks.amazonaws.com"
        }

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-otel-collector-role"
  }
}

resource "aws_iam_policy" "collector" {
  name        = "${var.cluster_name}-otel-collector-policy"
  description = "OpenTelemetry collector: CloudWatch Logs/Metrics write, telemetry archive write"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = concat(
      [
        # awscloudwatchlogs · awsemf exporter 가 쓰는 권한.
        # 로그 그룹은 Terraform 이 이미 만들었으므로 CreateLogGroup 은 주지 않는다 —
        # 수집기가 임의 경로를 만들지 못하게 하는 것이 목적이다.
        {
          Sid    = "WriteOwnLogGroups"
          Effect = "Allow"

          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogStreams",
            "logs:PutRetentionPolicy",
          ]

          Resource = [
            "${aws_cloudwatch_log_group.application.arn}:*",
            "${aws_cloudwatch_log_group.emf.arn}:*",
          ]
        },

        # DescribeLogGroups 는 리소스 수준 제한을 지원하지 않는다.
        {
          Sid      = "DescribeLogGroups"
          Effect   = "Allow"
          Action   = ["logs:DescribeLogGroups"]
          Resource = "*"
        },

        # 수집기는 마스킹된 값을 되돌릴 이유가 없다. Unmask 를 명시적으로 막는다.
        # 정책이 두 개 이상 붙어도 Deny 가 이긴다.
        {
          Sid      = "DenyUnmask"
          Effect   = "Deny"
          Action   = ["logs:Unmask"]
          Resource = "*"
        },

        # PutMetricData 는 리소스 제한이 없다. 네임스페이스로 좁힌다.
        {
          Sid      = "PutMetricDataInOwnNamespace"
          Effect   = "Allow"
          Action   = ["cloudwatch:PutMetricData"]
          Resource = "*"

          Condition = {
            StringEquals = {
              "cloudwatch:namespace" = [
                "BoA/Observability",
                "ContainerInsights",
              ]
            }
          }
        },

        # resourcedetection 프로세서의 eks 디텍터가 클러스터 정보를 읽는다.
        {
          Sid      = "DescribeOwnCluster"
          Effect   = "Allow"
          Action   = ["eks:DescribeCluster"]
          Resource = local.cluster_arn
        },

        # resourcedetection 의 ec2 디텍터가 노드 태그를 읽는다. IMDS 로 얻는 값
        # 외에 태그를 리소스 속성으로 붙이려면 필요하다.
        {
          Sid      = "DescribeEc2Tags"
          Effect   = "Allow"
          Action   = ["ec2:DescribeTags"]
          Resource = "*"
        },

      ],

      # 텔레메트리 장기 보관을 쓸 때만 S3 쓰기를 준다. 읽기·삭제는 주지 않는다 —
      # 수집기는 쓰기 전용이어야 하고, 지우는 것은 라이프사이클 규칙의 일이다.
      var.enable_telemetry_archive ? [
        {
          Sid    = "WriteTelemetryArchive"
          Effect = "Allow"

          Action = [
            "s3:PutObject",
            "s3:AbortMultipartUpload",
          ]

          Resource = "arn:${local.partition}:s3:::${local.telemetry_bucket_name}/*"
        },
        {
          Sid      = "ListTelemetryArchiveBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = "arn:${local.partition}:s3:::${local.telemetry_bucket_name}"
        },
      ] : []
    )
  })

  tags = {
    Name = "${var.cluster_name}-otel-collector-policy"
  }
}

resource "aws_iam_role_policy_attachment" "collector" {
  role       = aws_iam_role.collector.name
  policy_arn = aws_iam_policy.collector.arn
}

# 수집기 게이트웨이의 SA 를 위 역할에 연결한다.
# 이름이 gitops 의 ServiceAccount 와 정확히 같아야 한다 — 틀리면 조용히 자격증명이
# 안 붙고, 수집기는 "NoCredentialProviders" 로 exporter 만 실패한다.
resource "aws_eks_pod_identity_association" "collector" {
  cluster_name    = var.cluster_name
  namespace       = var.observability_namespace
  service_account = var.collector_service_account

  role_arn = aws_iam_role.collector.arn

  tags = {
    Name = "${var.cluster_name}-otel-collector-pia"
  }
}


# ===================================================
# GRAFANA — EKS Pod Identity (읽기 전용)
# ===================================================

resource "aws_iam_role" "grafana" {
  name = "${var.cluster_name}-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "pods.eks.amazonaws.com"
        }

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-grafana-role"
  }
}

# CloudWatch 데이터소스가 필요로 하는 읽기 권한.
# logs:Unmask 는 없다 — Grafana 화면에서도 계좌번호는 가려진 채 보여야 한다.
resource "aws_iam_policy" "grafana" {
  name        = "${var.cluster_name}-grafana-policy"
  description = "Grafana CloudWatch datasource: read-only, no logs:Unmask"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadMetrics"
        Effect = "Allow"

        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetInsightRuleReport",
        ]

        Resource = "*"
      },
      {
        Sid    = "ReadLogs"
        Effect = "Allow"

        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogGroupFields",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
        ]

        Resource = "*"
      },
      {
        Sid      = "DenyUnmask"
        Effect   = "Deny"
        Action   = ["logs:Unmask"]
        Resource = "*"
      },
      {
        Sid    = "ResolveDimensions"
        Effect = "Allow"

        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "tag:GetResources",
        ]

        Resource = "*"
      },
    ]
  })

  tags = {
    Name = "${var.cluster_name}-grafana-policy"
  }
}

resource "aws_iam_role_policy_attachment" "grafana" {
  role       = aws_iam_role.grafana.name
  policy_arn = aws_iam_policy.grafana.arn
}

resource "aws_eks_pod_identity_association" "grafana" {
  cluster_name    = var.cluster_name
  namespace       = var.observability_namespace
  service_account = var.grafana_service_account

  role_arn = aws_iam_role.grafana.arn

  tags = {
    Name = "${var.cluster_name}-grafana-pia"
  }
}


# ===================================================
# EXTERNAL SECRETS OPERATOR — EKS Pod Identity
# ===================================================

# ESO 컨트롤러가 Secrets Manager 를 읽는 역할. 이전에는 수집기 역할의
# ReadObservabilitySecrets 문이 이 권한을 대신했다(Secrets Store CSI 볼륨을
# 마운트하는 파드 자격증명으로 읽었기 때문). ESO 도입 후 컨트롤러 자신이
# 직접 읽으므로 그 문을 빼고 여기로 옮겼다 — gitops 변경 내역 11.7 참조.
resource "aws_iam_role" "eso" {
  name = "${var.cluster_name}-external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "pods.eks.amazonaws.com"
        }

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-external-secrets-role"
  }
}

# 경로는 /boa/observability* 로 좁힌다 — 앱 시크릿(/boa/application)은 못 읽는다.
# ClusterSecretStore 의 conditions.namespaces 가 참조 가능한 네임스페이스를
# monitoring · whatap-monitoring 으로 한번 더 좁혀 두 겹으로 막는다.
resource "aws_iam_policy" "eso" {
  name        = "${var.cluster_name}-external-secrets-policy"
  description = "External Secrets Operator: read /boa/observability* only"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadObservabilitySecrets"
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]

        Resource = [
          "arn:${local.partition}:secretsmanager:${var.region}:${local.account_id}:secret:${var.secret_path_prefix}*"
        ]
      },
    ]
  })

  tags = {
    Name = "${var.cluster_name}-external-secrets-policy"
  }
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}

# gitops 의 boa-external-secrets Application 이 serviceAccount.name 을
# external-secrets 로 고정해 둔다. 여기와 어긋나면 조용히 자격증명이 안 붙는다.
resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = var.eso_namespace
  service_account = var.eso_service_account

  role_arn = aws_iam_role.eso.arn

  tags = {
    Name = "${var.cluster_name}-external-secrets-pia"
  }
}


# ===================================================
# UNMASK 정책 — 만들지만 부착하지 않는다
# ===================================================

# 감사 시 원본을 봐야 할 때 사람이 의도적으로 자기 역할에 붙인다.
# 부착 자체가 CloudTrail 에 남으므로 "누가 언제 마스킹을 걷었는가"가 추적된다.
# 어떤 역할에도 붙이지 않는 것이 이 리소스의 요점이다.
resource "aws_iam_policy" "logs_unmask" {
  name        = "${var.cluster_name}-cloudwatch-logs-unmask"
  description = "DELIBERATE ATTACH ONLY - grants logs:Unmask for audit. Attaching is itself the audit event."

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid      = "UnmaskProtectedData"
        Effect   = "Allow"
        Action   = ["logs:Unmask"]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name       = "${var.cluster_name}-cloudwatch-logs-unmask"
    AttachedTo = "none-by-design"
  }
}

# 컨트롤러가 ALB·대상 그룹·리스너를 만들고 지울 권한. iam-policy.json 은 upstream 배포본이다.
resource "aws_iam_policy" "this" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = file("${path.module}/iam-policy.json")

  tags = {
    Name = "${var.cluster_name}-aws-load-balancer-controller"
  }
}

# AWS Load Balancer Controller가 사용할 IAM Role
resource "aws_iam_role" "this" {
  name = "${var.cluster_name}-aws-load-balancer-controller"

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
    Name = "${var.cluster_name}-aws-load-balancer-controller"
  }
}

# 위 IAM Role에 Load Balancer Controller IAM Policy 연결
resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

# 컨트롤러 파드가 쓸 ServiceAccount. 아래 Pod Identity 연결이 이 이름을 대상으로 한다.
# 주의 — automount_service_account_token = false 라 kube API 토큰이 마운트되지 않는다.
# 컨트롤러는 Ingress 를 watch 해야 하므로 차트가 파드 레벨에서 켜주는지 확인이 필요하다.
resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
  }
  automount_service_account_token = true
}

# 위 SA 를 위 IAM 역할에 연결. 이게 있어야 컨트롤러가 AWS API 를 호출한다.
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = kubernetes_service_account_v1.this.metadata[0].name
  role_arn        = aws_iam_role.this.arn
}

# 컨트롤러 본체. Ingress 어노테이션을 보고 서비스 ALB 를 만들고,
# TargetGroupBinding CRD 를 설치해 ops ALB 의 대상 그룹에 파드를 등록한다.
# gitops 의 overlays/eks/observability/grafana.yaml 이 그 CRD 를 써서
# Grafana 를 ops ALB 대상 그룹에 붙인다. 이 모듈이 없으면 그 리소스만
# 적용에 실패한다.
#
# 차트 버전은 var.chart_version 기본값 3.5.0 으로 고정된다. 호출부
# (aws-eks/main.tf)에서 덮어쓰지 않는다. 2026-09-27 기준 eks-charts
# 저장소의 최신 버전이다.
resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = var.namespace
  version    = var.chart_version
  set = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "region"
      value = var.region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "false"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    }
  ]

  depends_on = [
    kubernetes_service_account_v1.this,
    aws_eks_pod_identity_association.this
  ]
}

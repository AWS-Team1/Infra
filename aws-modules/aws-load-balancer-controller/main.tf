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

# aws-eks-platform이 같은 이름으로 관리하는 ServiceAccount를 IAM 역할에 연결한다.
# 이 리소스는 AWS API만 사용하므로 EKS 인프라 root에서 안전하게 관리할 수 있다.
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.this.arn
}

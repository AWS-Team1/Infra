# ===================================================
# EKS CLUSTER IAM ROLE
# ===================================================

# EKS 컨트롤 플레인이 맡는 역할. aws_eks_cluster 의 role_arn 으로 들어간다.
# 신뢰 주체는 eks.amazonaws.com — AWS 서비스가 직접 맡는다.
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-cluster-role"
  }
}


# 클러스터 역할에 AWS 관리형 정책을 붙인다. 이게 붙기 전에 클러스터가 생성되면
# 실패하므로, outputs.tf 의 cluster_role_arn 이 이 부착을 depends_on 으로 건다.
resource "aws_iam_role_policy_attachment" "cluster_eks_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ===================================================
# EKS MANAGED NODE GROUP IAM ROLE
# ===================================================

# 워커 노드 EC2 인스턴스가 맡는 역할. aws_eks_node_group 의 node_role_arn 으로 들어가고,
# Karpenter 가 노드를 띄울 때도 iam:PassRole 대상이 된다.
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-node-role"
  }
}


# ===================================================
# NODE IAM POLICIES
# ===================================================

# 노드가 클러스터에 합류하고 상태를 보고하는 데 필요한 권한(AWS 관리형).
resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}


# 노드가 ECR 에서 이미지를 당겨올 권한. 푸시는 못 한다 (PullOnly).
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}


# VPC CNI 가 파드에 ENI·보조 IP 를 붙이는 데 필요한 권한.
resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# 아래 locals.cluster_arn 과 Secrets Manager ARN 조립에 쓸 계정 ID.
data "aws_caller_identity" "current" {}

# ARN 의 파티션(aws / aws-cn / aws-us-gov). 상용 리전이면 "aws".
data "aws_partition" "current" {}

# 클러스터 리소스를 참조하지 않고 ARN 을 조립한다.
# var.cluster_name 은 루트가 넘기는 리터럴이고 data 두 개는 plan 시점에 확정되므로
# 클러스터가 없어도 계산된다. IAM 정책의 Resource 는 대상이 실재하지 않아도 유효하다.
locals {
  cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
}

# Karpenter 컨트롤러가 맡을 역할. 신뢰 주체가 pods.eks.amazonaws.com 이라
# EKS Pod Identity 로 karpenter 네임스페이스의 파드가 이걸 받는다.
resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller-role"

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
    Name = "${var.cluster_name}-karpenter-controller-role"
  }
}

# Karpenter 가 노드를 띄우고 지우는 데 필요한 권한.
# 클러스터 ARN 은 리소스 참조가 아니라 local.cluster_arn 문자열을 쓴다 — 모듈 순환 회피.
resource "aws_iam_policy" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # EC2 생성
      {
        Sid    = "AllowEC2InstanceActions"
        Effect = "Allow"

        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]

        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}::image/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}::snapshot/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:subnet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:capacity-reservation/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:placement-group/*"
        ]
      },

      # 생성한 EC2 / Launch Template 관리
      {
        Sid    = "AllowEC2LifecycleActions"
        Effect = "Allow"

        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]

        Resource = "*"
      },

      # EC2 리소스 조회
      {
        Sid    = "AllowEC2ReadActions"
        Effect = "Allow"

        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:DescribeCapacityReservations",
          "ec2:DescribePlacementGroups"
        ]

        Resource = "*"
      },

      # Amazon Linux AMI 등의 SSM Parameter 조회
      {
        Sid    = "AllowSSMReadActions"
        Effect = "Allow"

        Action = [
          "ssm:GetParameter"
        ]

        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.region}::parameter/aws/service/*"
      },

      # 가격 정보 조회
      {
        Sid    = "AllowPricingReadActions"
        Effect = "Allow"

        Action = [
          "pricing:GetProducts"
        ]

        Resource = "*"
      },

      # EKS Cluster 정보 조회
      {
        Sid    = "AllowEKSDescribeCluster"
        Effect = "Allow"

        Action = [
          "eks:DescribeCluster"
        ]

        Resource = local.cluster_arn
      },

      # 기존 Node Role을 Karpenter 노드에 전달
      {
        Sid    = "AllowPassingInstanceRole"
        Effect = "Allow"

        Action = [
          "iam:PassRole"
        ]

        Resource = aws_iam_role.node.arn

        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },

      # Karpenter가 Instance Profile 관리
      {
        Sid    = "AllowInstanceProfileActions"
        Effect = "Allow"

        Action = [
          "iam:CreateInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:ListInstanceProfiles"
        ]

        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-karpenter-controller-policy"
  }
}

# 위 정책을 Karpenter 역할에 부착.
resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# EBS CSI 드라이버 컨트롤러가 맡을 역할.
# kube-system/ebs-csi-controller-sa 가 Pod Identity 로 받는다.
resource "aws_iam_role" "ebs_csi_controller" {
  name = "${var.cluster_name}-ebs-csi-controller-role"

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
    Name = "${var.cluster_name}-ebs-csi-controller-role"
  }
}

# EBS 볼륨 생성·연결·스냅샷 권한(AWS 관리형).
resource "aws_iam_role_policy_attachment" "ebs_csi_controller" {
  role       = aws_iam_role.ebs_csi_controller.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# 노드 인스턴스 역할에 붙는 Secrets Manager 읽기 권한.
# 주의 — 노드 역할이라 그 노드의 모든 파드가 IMDS 로 접근할 수 있다.
# Secrets Store CSI 드라이버가 이 경로를 쓰고 있을 수 있어 제거 전 확인이 필요하다.
resource "aws_iam_policy" "node_secrets" {
  name = "${var.cluster_name}-node-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]

        Resource = [
          "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:/${var.project_name}/*"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-node-secrets-policy"
  }
}

# 위 정책을 노드 역할에 부착.
resource "aws_iam_role_policy_attachment" "node_secrets" {
  role       = aws_iam_role.node.name
  policy_arn = aws_iam_policy.node_secrets.arn
}

# ============================================================
# Bank of Anthos - EKS Pod Identity
# ============================================================

# 애플리케이션 파드가 맡는 역할. Pod Identity 로 bank-of-anthos ServiceAccount 에 연결된다.
# 연결 자체는 eks 모듈의 aws_eks_pod_identity_association 이 만든다.
resource "aws_iam_role" "bank_of_anthos" {
  name = "${var.project_name}-bank-of-anthos-sm"

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
    Name = "${var.project_name}-bank-of-anthos-sm"
  }
}


# 애플리케이션이 읽을 시크릿 범위. /boa/* 와 RDS 관리형 마스터 비밀번호(rds!db-*).
resource "aws_iam_policy" "bank_of_anthos_secrets" {
  name        = "${var.project_name}-bank-of-anthos-secrets"
  description = "Secrets Manager access for Bank of Anthos application"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]

        Resource = [
          "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:/${var.project_name}/*",

          # Phase 1:
          # RDS Managed Master Password secret
          "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!db-*"
        ]
      }
    ]
  })
}


# 위 정책을 애플리케이션 역할에 부착.
resource "aws_iam_role_policy_attachment" "bank_of_anthos_secrets" {
  role       = aws_iam_role.bank_of_anthos.name
  policy_arn = aws_iam_policy.bank_of_anthos_secrets.arn
}



# ===================================================
# EKS CLUSTER IAM ROLE
# ===================================================

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


resource "aws_iam_role_policy_attachment" "cluster_eks_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ===================================================
# EKS MANAGED NODE GROUP IAM ROLE
# ===================================================

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

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}


resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}


resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

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

        Resource = aws_eks_cluster.main.arn
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

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_controller.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}

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

resource "aws_iam_role_policy_attachment" "ebs_csi_controller" {
  role       = aws_iam_role.ebs_csi_controller.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_controller.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}


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

resource "aws_iam_role_policy_attachment" "node_secrets" {
  role       = aws_iam_role.node.name
  policy_arn = aws_iam_policy.node_secrets.arn
}

# ============================================================
# Bank of Anthos - EKS Pod Identity
# ============================================================

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


resource "aws_iam_role_policy_attachment" "bank_of_anthos_secrets" {
  role       = aws_iam_role.bank_of_anthos.name
  policy_arn = aws_iam_policy.bank_of_anthos_secrets.arn
}


resource "aws_eks_pod_identity_association" "bank_of_anthos" {
  cluster_name = aws_eks_cluster.main.name

  namespace       = "default"
  service_account = "bank-of-anthos"

  role_arn = aws_iam_role.bank_of_anthos.arn
}


resource "kubernetes_cluster_role_v1" "secrets_store_sync" {
  metadata {
    name = "secretprovidersyncing-role"
  }
  depends_on = [
    aws_eks_access_policy_association.code_server_admin
  ]

  rule {
    api_groups = [""]

    resources = [
      "secrets"
    ]

    verbs = [
      "get",
      "create",
      "update",
      "patch",
      "delete",
      "list",
      "watch"
    ]
  }
}

resource "kubernetes_cluster_role_binding_v1" "secrets_store_sync" {
  metadata {
    name = "secretprovidersyncing-rolebinding"
  }

  depends_on = [
    aws_eks_access_policy_association.code_server_admin
  ]

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.secrets_store_sync.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "secrets-store-csi-driver"
    namespace = "aws-secrets-manager"
  }
}

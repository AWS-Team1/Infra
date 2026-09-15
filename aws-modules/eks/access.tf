# ===================================================
# EKS ACCESS ENTRY - CODE SERVER
# ===================================================

# 코드 서버의 IAM 역할을 클러스터 사용자로 등록한다.
# authentication_mode = API 라서 aws-auth ConfigMap 이 아니라 이 리소스를 쓴다.
resource "aws_eks_access_entry" "code_server" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.code_server_role_arn

  type = "STANDARD"
}

# IAM 그룹의 구성원 조회
data "aws_iam_group" "console_users" {
  group_name = var.console_user_group_name
}

# 사용자 ARN을 for_each용 Map으로 변환
locals {
  console_user_arns = {
    for user in data.aws_iam_group.console_users.users :
    user.arn => user.arn
  }
}

# 그룹 구성원마다 EKS Access Entry 생성
resource "aws_eks_access_entry" "console_users" {
  for_each = local.console_user_arns

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"
}

# 그룹 구성원마다 EKS 조회 정책 연결
resource "aws_eks_access_policy_association" "console_users_view" {
  for_each = local.console_user_arns

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.console_users
  ]
}


# ===================================================
# EKS ACCESS POLICY - CLUSTER ADMIN
# ===================================================

# 위 access entry 에 클러스터 관리자 권한을 부여한다.
# 이게 있어야 코드 서버에서 kubectl 이 먹는다.
resource "aws_eks_access_policy_association" "code_server_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.code_server_role_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.code_server
  ]
}

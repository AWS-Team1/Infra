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

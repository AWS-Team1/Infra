# ===================================================
# EKS ACCESS ENTRY - CODE SERVER
# ===================================================

resource "aws_eks_access_entry" "code_server" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.code_server_role_arn

  type = "STANDARD"
}


# ===================================================
# EKS ACCESS POLICY - CLUSTER ADMIN
# ===================================================

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

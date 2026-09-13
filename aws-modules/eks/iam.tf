resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = var.karpenter_role_arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = var.ebs_csi_role_arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}


resource "aws_eks_pod_identity_association" "bank_of_anthos" {
  cluster_name = aws_eks_cluster.main.name

  namespace       = "default"
  service_account = "bank-of-anthos"

  role_arn = var.bank_of_anthos_role_arn
}

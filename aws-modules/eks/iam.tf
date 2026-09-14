# karpenter 네임스페이스의 karpenter SA 를 eks-iam 의 Karpenter 역할에 연결.
# pod-identity-agent 애드온이 먼저 있어야 동작한다.
resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = var.karpenter_role_arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}

# EBS CSI 컨트롤러 SA 를 eks-iam 의 ebs-csi 역할에 연결.
# addons.tf 의 ebs_csi 애드온이 이 연결을 depends_on 으로 기다린다.
resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = var.ebs_csi_role_arn

  depends_on = [
    aws_eks_addon.pod_identity_agent
  ]
}


# 애플리케이션 SA 를 eks-iam 의 bank-of-anthos 역할에 연결.
# 주의 — 네임스페이스가 default 다. 라이브 앱이 bank-of-anthos 네임스페이스라면 맞지 않는다.
resource "aws_eks_pod_identity_association" "bank_of_anthos" {
  cluster_name = aws_eks_cluster.main.name

  namespace       = "default"
  service_account = "bank-of-anthos"

  role_arn = var.bank_of_anthos_role_arn
}

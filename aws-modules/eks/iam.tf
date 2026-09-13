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

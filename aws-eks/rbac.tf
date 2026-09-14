# Secrets Store CSI 드라이버가 Secret 을 동기화할 수 있게 하는 RBAC.
# aws-modules/eks 에 두면 그 모듈이 kubernetes provider 를 요구하므로 루트에 둔다.

resource "kubernetes_cluster_role_v1" "secrets_store_sync" {
  metadata {
    name = "secretprovidersyncing-role"
  }

  depends_on = [module.eks]

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

# 위 ClusterRole 을 Secrets Store CSI 드라이버의 SA 에 부여한다.
# 그 SA 는 eks 모듈의 aws-secrets-store-csi-driver-provider 애드온이 만든다.
resource "kubernetes_cluster_role_binding_v1" "secrets_store_sync" {
  metadata {
    name = "secretprovidersyncing-rolebinding"
  }

  depends_on = [module.eks]

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

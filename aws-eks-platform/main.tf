data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = module.environment.state_bucket
    key    = "aws/core/terraform.tfstate"
    region = module.environment.aws_region
  }
}

module "aws_load_balancer_controller" {
  source = "../aws-modules/aws-load-balancer-controller-platform"

  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  region       = module.environment.aws_region
  vpc_id       = data.terraform_remote_state.core.outputs.vpc_id
}

resource "kubernetes_cluster_role_v1" "secrets_store_sync" {
  metadata { name = "secretprovidersyncing-role" }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "create", "update", "patch", "delete", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "secrets_store_sync" {
  metadata { name = "secretprovidersyncing-rolebinding" }

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

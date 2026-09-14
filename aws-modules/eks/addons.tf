# ===================================================
# EKS ADD-ON VERSION LOOKUP
# ===================================================

# 애드온 버전을 클러스터 버전에 맞춰 자동 선택한다.
# 버전을 손으로 박지 않아 클러스터를 올릴 때 같이 따라간다.

# 파드에 VPC IP 를 직접 할당하는 CNI.
data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.kubernetes_version
  most_recent        = true

}

# 클러스터 내부 DNS.
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

# 노드의 Service 라우팅(iptables/IPVS) 담당.
data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

# PersistentVolume 용 EBS 드라이버.
data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

# 파드가 IAM 역할을 받게 해주는 에이전트. IRSA 대신 쓰는 방식이다.
data "aws_eks_addon_version" "pod_identity_agent" {
  addon_name         = "eks-pod-identity-agent"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}


# ===================================================
# VPC CNI
# ===================================================

# enableNetworkPolicy=true 로 켠다. boa/k8s 의 NetworkPolicy 가 이걸 필요로 한다.
# 노드그룹이 있어야 애드온 파드가 뜨므로 depends_on 을 건다.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.vpc_cni.version

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_node_group.main
  ]
}


# ===================================================
# COREDNS
# ===================================================

# 클러스터 DNS. 서비스 디스커버리가 이것에 의존한다 —
# 애플리케이션이 userservice:8080 같은 이름으로 서로를 찾는다.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_node_group.main
  ]
}


# ===================================================
# KUBE-PROXY
# ===================================================

# 노드에서 Service ClusterIP 를 파드로 넘기는 규칙을 관리한다.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_node_group.main
  ]
}


# ===================================================
# EBS CSI DRIVER
# ===================================================

# PersistentVolumeClaim 을 EBS 볼륨으로 만든다.
# iam.tf 의 ebs_csi Pod Identity 연결이 먼저 있어야 자격증명을 받는다.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_pod_identity_association.ebs_csi
  ]
}


# ===================================================
# POD IDENTITY AGENT
# ===================================================

# 파드에 IAM 자격증명을 주입하는 에이전트.
# iam.tf 의 Pod Identity 연결 3건이 전부 이 애드온을 depends_on 으로 기다린다.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = data.aws_eks_addon_version.pod_identity_agent.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_node_group.main
  ]
}

# Secrets Manager 를 CSI 볼륨으로 마운트하는 AWS provider 애드온.
# 버전 조회 기준이 다른 넷과 달리 var.kubernetes_version 이 아니라
# 실제 클러스터 버전이다 — 자동 업그레이드되면 갈라질 수 있다.

data "aws_eks_addon_version" "secrets_store" {
  addon_name         = "aws-secrets-store-csi-driver-provider"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

# Secrets Manager 를 CSI 볼륨으로 마운트하는 AWS provider.
# 이 애드온이 upstream secrets-store-csi-driver 를 sub-chart 로 함께 설치한다
# (네임스페이스 aws-secrets-manager). aws-eks/rbac.tf 의 RBAC 가 그 SA 를 대상으로 한다.
resource "aws_eks_addon" "secrets_store" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "aws-secrets-store-csi-driver-provider"
  addon_version = data.aws_eks_addon_version.secrets_store.version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_node_group.main
  ]
}

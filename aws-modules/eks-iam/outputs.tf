output "cluster_role_arn" {
  value = aws_iam_role.cluster.arn

  # 정책 부착 전에 클러스터가 만들어지면 실패한다.
  depends_on = [aws_iam_role_policy_attachment.cluster_eks_policy]
}

output "node_role_arn" {
  value = aws_iam_role.node.arn

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_secrets
  ]
}

output "node_role_name" {
  value = aws_iam_role.node.name
}

output "karpenter_role_arn" {
  value      = aws_iam_role.karpenter_controller.arn
  depends_on = [aws_iam_role_policy_attachment.karpenter_controller]
}

output "ebs_csi_role_arn" {
  value      = aws_iam_role.ebs_csi_controller.arn
  depends_on = [aws_iam_role_policy_attachment.ebs_csi_controller]
}

output "bank_of_anthos_role_arn" {
  value      = aws_iam_role.bank_of_anthos.arn
  depends_on = [aws_iam_role_policy_attachment.bank_of_anthos_secrets]
}

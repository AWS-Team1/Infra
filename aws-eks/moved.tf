moved {
  from = module.eks.aws_eks_access_entry.console_user
  to   = module.eks.aws_eks_access_entry.console_users["arn:aws:iam::769413326616:user/dohyun"]
}

moved {
  from = module.eks.aws_eks_access_policy_association.console_user_view
  to   = module.eks.aws_eks_access_policy_association.console_users_view["arn:aws:iam::769413326616:user/dohyun"]
}

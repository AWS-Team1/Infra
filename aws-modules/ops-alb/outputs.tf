output "alb_arn" {
  value = aws_lb.this.arn
}

# DNS 레코드를 밖에서 잡을 때 쓰는 짝이다.
# A(alias) 레코드의 대상 이름과 대상 영역 ID 가 이 둘이다.
output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

# gitops 의 TargetGroupBinding 에 spec.networking.ingress 로 넣을 값이다.
# 이게 없으면 컨트롤러가 파드 SG 를 열어주지 않아 헬스체크가 전부 실패한다.
output "alb_security_group_id" {
  value = aws_security_group.this.id
}

# gitops 의 environments/<env>/aws.env 의 ARGOCD_TARGET_GROUP_ARN 에 넣는다.
output "argocd_target_group_arn" {
  value = aws_lb_target_group.argocd.arn
}

# 최종 접속 주소. 다만 이 모듈은 DNS 레코드를 만들지 않으므로,
# argocd_host 를 alb_dns_name 으로 보내는 레코드를 밖에서 잡기 전에는 열리지 않는다.
output "argocd_url" {
  value = "https://${var.argocd_host}"
}

# 관측성 대상 그룹을 나중에 붙일 때 쓸 리스너다.
output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

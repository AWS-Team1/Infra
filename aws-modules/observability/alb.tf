# ===================================================
# GRAFANA — ops ALB 대상 그룹 · 리스너 규칙
# ===================================================

# ops-alb 모듈의 argocd 대상 그룹과 같은 형태다. 대상 등록은 Terraform 이 하지 않고
# 클러스터의 TargetGroupBinding 이 파드 IP 를 넣는다. 그래서 생성 직후 대상은 0개이고
# 그것이 정상이다.
#
# Grafana 는 기본값으로 TLS 를 쓰지 않으므로 argocd 와 달리 insecure 설정이 필요 없다.
# 다만 서브패스로 서비스하려면 GF_SERVER_ROOT_URL 이 필요한데, 호스트명으로 붙이므로
# 이 구성에서는 불필요하다.
resource "aws_lb_target_group" "grafana" {
  name        = "${var.project_name}-grafana-tg"
  target_type = "ip"
  vpc_id      = var.vpc_id

  port     = var.grafana_target_port
  protocol = "HTTP"

  health_check {
    enabled  = true
    protocol = "HTTP"
    path     = "/api/health"
    port     = "traffic-port"
    matcher  = "200"

    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-grafana-tg"
  }
}

# ops-alb 의 HTTPS 리스너에 규칙을 더한다. 리스너는 aws-ops 가 소유하고,
# 규칙만 이 모듈이 소유한다 — 리스너 자체를 건드리지 않으므로 aws-ops 의 상태와
# 충돌하지 않는다.
#
# 우선순위 200 은 ops-alb 모듈이 주석으로 "관측성은 200번대"라고 비워 둔 대역이다.
resource "aws_lb_listener_rule" "grafana" {
  listener_arn = var.ops_alb_https_listener_arn
  priority     = var.grafana_listener_rule_priority

  condition {
    host_header {
      values = [var.grafana_host]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  tags = {
    Name = "${var.project_name}-ops-alb-rule-grafana"
  }
}

# Keep the existing Argo CD 8080 rule owned by aws-ops and add only the
# Grafana target/health-check path required by this root.
resource "aws_vpc_security_group_egress_rule" "grafana" {
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = var.ops_alb_security_group_id
  description       = "Grafana targets in ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.grafana_target_port
  to_port           = var.grafana_target_port
  cidr_ipv4         = each.value

  tags = {
    Name = "${var.project_name}-ops-alb-to-grafana"
  }
}

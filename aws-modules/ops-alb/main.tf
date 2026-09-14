# ===================================================
# ACM / ROUTE53 참조
# ===================================================
# ACM 과 DNS 는 Terraform 관리 대상이 아니다. 이미 있는 것을 읽어 쓴다.

data "aws_acm_certificate" "this" {
  domain      = var.certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name
  private_zone = false
}


# ===================================================
# SECURITY GROUP
# ===================================================
# aws_security_group 은 egress 블록이 없으면 AWS 기본 all-egress 를 제거한다.
# 아웃바운드를 명시하지 않으면 ALB 가 대상에 닿지 못한다.

resource "aws_security_group" "this" {
  name        = "${var.project_name}-ops-alb-sg"
  description = "Security group for ops ALB (ArgoCD, monitoring)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-ops-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.this.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  description = "HTTP from Internet (redirects to HTTPS)"

  tags = {
    Name = "${var.project_name}-ops-alb-in-80"
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.this.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "HTTPS from Internet"

  tags = {
    Name = "${var.project_name}-ops-alb-in-443"
  }
}

# 대상은 프라이빗 서브넷의 파드 IP 다 (target_type = ip).
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = aws_security_group.this.id

  cidr_ipv4   = each.value
  from_port   = var.argocd_target_port
  to_port     = var.argocd_target_port
  ip_protocol = "tcp"

  description = "To targets in private subnet ${each.value}"

  tags = {
    Name = "${var.project_name}-ops-alb-out-${var.argocd_target_port}-${each.value}"
  }
}


# ===================================================
# APPLICATION LOAD BALANCER
# ===================================================

resource "aws_lb" "this" {
  name               = "${var.project_name}-ops-alb"
  load_balancer_type = "application"
  internal           = false

  subnets         = var.public_subnet_ids
  security_groups = [aws_security_group.this.id]

  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Name = "${var.project_name}-ops-alb"
  }
}


# ===================================================
# TARGET GROUP — ArgoCD
# ===================================================
# 대상 등록은 Terraform 이 하지 않는다. 클러스터의 TargetGroupBinding 이
# 파드 IP 를 여기에 넣는다. 그래서 생성 직후에는 대상이 0개이고, 그것이 정상이다.
#
# argocd-server 는 기본값으로 자체 서명 TLS 를 켜고 HTTP 를 HTTPS 로
# 리다이렉트한다. 대상 그룹이 HTTP 로 보내므로 values.yaml 에
# server.insecure = true 가 필요하다. 없으면 리다이렉트 루프가 된다.

resource "aws_lb_target_group" "argocd" {
  name        = "${var.project_name}-argocd-tg"
  target_type = "ip"
  vpc_id      = var.vpc_id

  port     = var.argocd_target_port
  protocol = "HTTP"

  health_check {
    enabled  = true
    protocol = "HTTP"
    path     = "/healthz"
    port     = "traffic-port"
    matcher  = "200"

    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-argocd-tg"
  }
}


# ===================================================
# LISTENERS
# ===================================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "${var.project_name}-ops-alb-http"
  }
}

# 기본 동작은 404 다. 호스트별 라우팅은 전부 리스너 규칙으로 붙인다.
# Grafana · Loki · Tempo 가 나중에 들어올 자리다.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy      = var.ssl_policy
  certificate_arn = data.aws_acm_certificate.this.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = {
    Name = "${var.project_name}-ops-alb-https"
  }
}

# 우선순위 대역 — argocd 100번대, 관측성은 200번대로 둔다.
resource "aws_lb_listener_rule" "argocd" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  condition {
    host_header {
      values = [var.argocd_host]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.argocd.arn
  }

  tags = {
    Name = "${var.project_name}-ops-alb-rule-argocd"
  }
}


# ===================================================
# DNS
# ===================================================

resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.argocd_host
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

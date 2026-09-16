# JWT 검증용 공개키를 담을 자리. 값(secret_version)은 Terraform 이 넣지 않는다.
# userservice 가 서명하고 나머지 서비스가 이 키로 검증한다.
resource "aws_secretsmanager_secret" "jwt_public" {
  name                    = "/${var.project_name}/jwt/public"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-jwt-public"
  }
}

# JWT 서명용 개인키를 담을 자리. 값은 별도 절차로 주입한다.
resource "aws_secretsmanager_secret" "jwt_private" {
  name                    = "/${var.project_name}/jwt/private"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-jwt-private"
  }
}

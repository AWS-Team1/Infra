resource "aws_secretsmanager_secret" "jwt_public" {
  name = "/${var.project_name}/jwt/public"

  tags = {
    Name = "${var.project_name}-jwt-public"
  }
}

resource "aws_secretsmanager_secret" "jwt_private" {
  name = "/${var.project_name}/jwt/private"

  tags = {
    Name = "${var.project_name}-jwt-private"
  }
}

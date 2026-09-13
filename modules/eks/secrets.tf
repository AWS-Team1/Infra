resource "aws_secretsmanager_secret" "jwt_public" {
  name = "/project/jwt/public"

  tags = {
    Name = "project-jwt-public"
  }
}

resource "aws_secretsmanager_secret" "jwt_private" {
  name = "/project/jwt/private"

  tags = {
    Name = "project-jwt-private"
  }
}

# =========================================================
# 보존 JWT Secret 자동 입양
#
# /boa/jwt/public · /boa/jwt/private 는 인프라를 다시 만들어도 값이 살아있어야
# 하는 시크릿이다(이미 발급된 JWT를 검증하는 키 — 지우고 새로 만들면 기존 토큰이
# 전부 무효가 된다). 그래서 이 root의 state 밖에서, 이전 apply나 수동 조치로
# 이미 존재할 수 있다. 그 상태에서 그냥 apply하면 이미 있는 시크릿을 새로
# 만들려다 ResourceExistsException 이 난다.
#
# 지금까지는 .github/workflows/terraform-apply.yml 의 "Adopt preserved JWT
# secrets" 단계(쉘 스크립트)가 CI에서만 이 조건분기를 대신해 줬다 — 로컬에서
# 직접 apply하면 그 단계가 없어서 매번 이 에러를 만난다. 여기서는 같은 로직을
# Terraform 코드로 옮겨 로컬·CI 양쪽에서 동일하게 동작하게 한다.
#
# 복수형 data source(aws_secretsmanager_secrets) + filter 를 쓰는 이유 —
# 단수형(aws_secretsmanager_secret) data source는 대상이 없으면 즉시 에러를
# 내서 "있으면 가져오고 없으면 새로 만든다"는 조건분기를 만들 수 없다. 복수형은
# 0개여도 에러 없이 빈 목록을 준다 — 그 빈 목록/한 개짜리 목록을 import 블록의
# for_each 에 그대로 흘려보낸다.
#
#   0개 → import 블록이 아무 인스턴스도 만들지 않는다. module.eks 의 resource
#         블록이 평소대로 새로 만든다.
#   1개 → 그 ARN 을 이 root의 state 로 가져온다. 이후 plan에는 변경 없음으로 뜬다.
#
# filter의 "name" 키는 완전일치가 아니라 부분일치일 수 있다 — 이 계정에 이
# 경로를 부분 문자열로 포함하는 다른 시크릿이 없다는 전제다. 새 시크릿을
# /boa/jwt/public 근처 이름으로 만들 계획이 있다면 이 전제를 다시 확인한다.
#
# CI 스크립트는 그대로 둔다 — terraform state list 로 먼저 확인하고 이미
# 관리 중이면 즉시 return 하므로, 이 import 블록으로 먼저 편입된 뒤에도
# 안전하게 no-op 이다.
# =========================================================

data "aws_secretsmanager_secrets" "jwt_public_existing" {
  filter {
    name   = "name"
    values = ["/boa/jwt/public"]
  }
}

data "aws_secretsmanager_secrets" "jwt_private_existing" {
  filter {
    name   = "name"
    values = ["/boa/jwt/private"]
  }
}

import {
  for_each = toset(data.aws_secretsmanager_secrets.jwt_public_existing.arns)

  to = module.eks.aws_secretsmanager_secret.jwt_public
  id = each.value
}

import {
  for_each = toset(data.aws_secretsmanager_secrets.jwt_private_existing.arns)

  to = module.eks.aws_secretsmanager_secret.jwt_private
  id = each.value
}

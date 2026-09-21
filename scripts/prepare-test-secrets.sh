#!/usr/bin/env bash
set -Eeuo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"

copy_current_value() {
  local source_name="$1"
  local destination_name="$2"

  aws secretsmanager get-secret-value \
    --region "$REGION" \
    --secret-id "$source_name" \
    --query SecretString \
    --output text |
    aws secretsmanager put-secret-value \
      --region "$REGION" \
      --secret-id "$destination_name" \
      --secret-string file:///dev/stdin \
      --output json >/dev/null

  echo "복사 완료: $source_name -> $destination_name"
}

for command_name in aws jq terraform; do
  command -v "$command_name" >/dev/null || {
    echo "ERROR: 필수 명령 없음: $command_name" >&2
    exit 1
  }
done

copy_current_value /boa/jwt/private /boa-test/jwt/private
copy_current_value /boa/jwt/public /boa-test/jwt/public
copy_current_value /boa/database/app /boa-test/database/app
copy_current_value /boa/database/accounts /boa-test/database/accounts
copy_current_value /boa/database/ledger /boa-test/database/ledger

test_rds_master_secret_arn="$(terraform -chdir="$(dirname "$0")/../aws-test-rds" output -raw master_user_secret_arn)"
copy_current_value "$test_rds_master_secret_arn" /boa-test/database/master
unset test_rds_master_secret_arn

aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id /boa-test/valkey/credentials \
  --query SecretString \
  --output text |
  jq -e '(.username == "boa-test-app") and (.password | type == "string" and length >= 16)' >/dev/null

echo "Valkey Secret 형식 검증 성공: /boa-test/valkey/credentials"

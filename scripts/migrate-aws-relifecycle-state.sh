#!/usr/bin/env bash
set -Eeuo pipefail

MODE=${1:---print}
case "$MODE" in
  --print|--execute) ;;
  *) echo "usage: STATE_BACKUP_DIR=/path $0 [--print|--execute]" >&2; exit 2 ;;
esac

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BACKEND_CONFIG="$REPO_ROOT/env/backend.hcl"
EXPECTED_ACCOUNT=769413326616

commands() {
  cat <<'COMMANDS'
terraform -chdir=persistent import aws_secretsmanager_secret.jwt_public 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/jwt/public-1HxMV3'
terraform -chdir=persistent import aws_secretsmanager_secret.jwt_private 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/jwt/private-oHogZ3'
terraform -chdir=persistent import aws_secretsmanager_secret.app_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/app-jFdqLv'
terraform -chdir=persistent import aws_secretsmanager_secret.accounts_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/accounts-z9LhFP'
terraform -chdir=persistent import aws_secretsmanager_secret.ledger_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/ledger-9TXa7G'
terraform -chdir=persistent import aws_secretsmanager_secret_version.app_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/app-jFdqLv|terraform-BIUKZyCyMrT2PeX9qIVq8EWdx2'
terraform -chdir=persistent import aws_secretsmanager_secret_version.accounts_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/accounts-z9LhFP|terraform-yQT8QF7doEP7QnzxuBP8RkbTpv'
terraform -chdir=persistent import aws_secretsmanager_secret_version.ledger_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/ledger-9TXa7G|terraform-nbAdZx8hhfb3PE4lk0uqu1SWlN'
terraform -chdir=aws-eks-platform import 'module.aws_load_balancer_controller.kubernetes_service_account_v1.this' 'kube-system/aws-load-balancer-controller'
terraform -chdir=aws-eks-platform import 'module.aws_load_balancer_controller.helm_release.this' 'kube-system/aws-load-balancer-controller'
terraform -chdir=aws-eks-platform import kubernetes_cluster_role_v1.secrets_store_sync 'secretprovidersyncing-role'
terraform -chdir=aws-eks-platform import kubernetes_cluster_role_binding_v1.secrets_store_sync 'secretprovidersyncing-rolebinding'
terraform -chdir=aws-eks state rm module.eks.aws_secretsmanager_secret.jwt_public module.eks.aws_secretsmanager_secret.jwt_private module.aws_load_balancer_controller.kubernetes_service_account_v1.this module.aws_load_balancer_controller.helm_release.this kubernetes_cluster_role_v1.secrets_store_sync kubernetes_cluster_role_binding_v1.secrets_store_sync
terraform -chdir=aws-db-bootstrap state rm aws_secretsmanager_secret.app_database aws_secretsmanager_secret.accounts_database aws_secretsmanager_secret.ledger_database aws_secretsmanager_secret_version.app_database aws_secretsmanager_secret_version.accounts_database aws_secretsmanager_secret_version.ledger_database
COMMANDS
}

if [[ "$MODE" == --print ]]; then
  commands
  exit 0
fi

[[ ${CONFIRM_STATE_MIGRATION:-} == MIGRATE-AWS-RELIFECYCLE ]] || {
  echo "set CONFIRM_STATE_MIGRATION=MIGRATE-AWS-RELIFECYCLE" >&2
  exit 1
}
[[ -n ${STATE_BACKUP_DIR:-} && -d "$STATE_BACKUP_DIR" ]] || {
  echo "STATE_BACKUP_DIR must reference the verified state-pull backup" >&2
  exit 1
}
for root in aws-core aws-rds aws-cache aws-ops aws-eks aws-db-bootstrap; do
  test -s "$STATE_BACKUP_DIR/$root.json"
done
test "$(aws sts get-caller-identity --query Account --output text)" = "$EXPECTED_ACCOUNT"

for root in persistent aws-eks-platform aws-eks aws-db-bootstrap; do
  terraform -chdir="$REPO_ROOT/$root" init -reconfigure -backend-config="$BACKEND_CONFIG" -input=false
done

source_address_exists() {
  terraform -chdir="$REPO_ROOT/$1" state list | grep -Fxq "$2"
}

for address in module.eks.aws_secretsmanager_secret.jwt_public module.eks.aws_secretsmanager_secret.jwt_private module.aws_load_balancer_controller.kubernetes_service_account_v1.this module.aws_load_balancer_controller.helm_release.this kubernetes_cluster_role_v1.secrets_store_sync kubernetes_cluster_role_binding_v1.secrets_store_sync; do
  source_address_exists aws-eks "$address"
done
for address in aws_secretsmanager_secret.app_database aws_secretsmanager_secret.accounts_database aws_secretsmanager_secret.ledger_database aws_secretsmanager_secret_version.app_database aws_secretsmanager_secret_version.accounts_database aws_secretsmanager_secret_version.ledger_database; do
  source_address_exists aws-db-bootstrap "$address"
done

for secret in /boa/jwt/public /boa/jwt/private /boa/database/app /boa/database/accounts /boa/database/ledger; do
  aws secretsmanager describe-secret --secret-id "$secret" --query ARN --output text >/dev/null
done
kubectl -n kube-system get serviceaccount aws-load-balancer-controller >/dev/null
kubectl get clusterrole secretprovidersyncing-role >/dev/null
kubectl get clusterrolebinding secretprovidersyncing-rolebinding >/dev/null
helm -n kube-system status aws-load-balancer-controller >/dev/null

terraform -chdir="$REPO_ROOT/persistent" import aws_secretsmanager_secret.jwt_public 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/jwt/public-1HxMV3'
terraform -chdir="$REPO_ROOT/persistent" import aws_secretsmanager_secret.jwt_private 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/jwt/private-oHogZ3'
terraform -chdir="$REPO_ROOT/persistent" import aws_secretsmanager_secret.app_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/app-jFdqLv'
terraform -chdir="$REPO_ROOT/persistent" import aws_secretsmanager_secret.accounts_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/accounts-z9LhFP'
terraform -chdir="$REPO_ROOT/persistent" import aws_secretsmanager_secret.ledger_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/ledger-9TXa7G'
terraform -chdir="$REPO_ROOT/persistent" import aws_secretsmanager_secret_version.app_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/app-jFdqLv|terraform-BIUKZyCyMrT2PeX9qIVq8EWdx2'
terraform -chdir="$REPO_ROOT/persistent" import aws_secretsmanager_secret_version.accounts_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/accounts-z9LhFP|terraform-yQT8QF7doEP7QnzxuBP8RkbTpv'
terraform -chdir="$REPO_ROOT/persistent" import aws_secretsmanager_secret_version.ledger_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/ledger-9TXa7G|terraform-nbAdZx8hhfb3PE4lk0uqu1SWlN'

terraform -chdir="$REPO_ROOT/aws-eks-platform" import 'module.aws_load_balancer_controller.kubernetes_service_account_v1.this' 'kube-system/aws-load-balancer-controller'
terraform -chdir="$REPO_ROOT/aws-eks-platform" import 'module.aws_load_balancer_controller.helm_release.this' 'kube-system/aws-load-balancer-controller'
terraform -chdir="$REPO_ROOT/aws-eks-platform" import kubernetes_cluster_role_v1.secrets_store_sync 'secretprovidersyncing-role'
terraform -chdir="$REPO_ROOT/aws-eks-platform" import kubernetes_cluster_role_binding_v1.secrets_store_sync 'secretprovidersyncing-rolebinding'

test "$(terraform -chdir="$REPO_ROOT/persistent" state list | grep -c '^aws_secretsmanager_')" -eq 8
test "$(terraform -chdir="$REPO_ROOT/aws-eks-platform" state list | grep -Ec 'helm_release|kubernetes_')" -eq 4

state_id() {
  terraform -chdir="$REPO_ROOT/$1" state show -no-color "$2" |
    awk -F' = ' '/^[[:space:]]*id[[:space:]]*=/{gsub(/"/, "", $2); print $2; exit}'
}
verify_id() {
  local actual
  actual=$(state_id "$1" "$2")
  [[ "$actual" == "$3" ]] || {
    echo "destination ID mismatch: $1 / $2: $actual != $3" >&2
    exit 1
  }
}

verify_id persistent aws_secretsmanager_secret.jwt_public 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/jwt/public-1HxMV3'
verify_id persistent aws_secretsmanager_secret.jwt_private 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/jwt/private-oHogZ3'
verify_id persistent aws_secretsmanager_secret.app_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/app-jFdqLv'
verify_id persistent aws_secretsmanager_secret.accounts_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/accounts-z9LhFP'
verify_id persistent aws_secretsmanager_secret.ledger_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/ledger-9TXa7G'
verify_id persistent aws_secretsmanager_secret_version.app_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/app-jFdqLv|terraform-BIUKZyCyMrT2PeX9qIVq8EWdx2'
verify_id persistent aws_secretsmanager_secret_version.accounts_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/accounts-z9LhFP|terraform-yQT8QF7doEP7QnzxuBP8RkbTpv'
verify_id persistent aws_secretsmanager_secret_version.ledger_database 'arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/ledger-9TXa7G|terraform-nbAdZx8hhfb3PE4lk0uqu1SWlN'
verify_id aws-eks-platform module.aws_load_balancer_controller.kubernetes_service_account_v1.this 'kube-system/aws-load-balancer-controller'
verify_id aws-eks-platform module.aws_load_balancer_controller.helm_release.this 'aws-load-balancer-controller'
verify_id aws-eks-platform kubernetes_cluster_role_v1.secrets_store_sync 'secretprovidersyncing-role'
verify_id aws-eks-platform kubernetes_cluster_role_binding_v1.secrets_store_sync 'secretprovidersyncing-rolebinding'

terraform -chdir="$REPO_ROOT/aws-eks" state rm module.eks.aws_secretsmanager_secret.jwt_public module.eks.aws_secretsmanager_secret.jwt_private module.aws_load_balancer_controller.kubernetes_service_account_v1.this module.aws_load_balancer_controller.helm_release.this kubernetes_cluster_role_v1.secrets_store_sync kubernetes_cluster_role_binding_v1.secrets_store_sync
terraform -chdir="$REPO_ROOT/aws-db-bootstrap" state rm aws_secretsmanager_secret.app_database aws_secretsmanager_secret.accounts_database aws_secretsmanager_secret.ledger_database aws_secretsmanager_secret_version.app_database aws_secretsmanager_secret_version.accounts_database aws_secretsmanager_secret_version.ledger_database

for root in persistent aws-eks-platform aws-eks aws-db-bootstrap; do
  terraform -chdir="$REPO_ROOT/$root" plan -input=false -lock-timeout=5m -out=migration-verification.tfplan
  terraform -chdir="$REPO_ROOT/$root" show -json migration-verification.tfplan |
    jq -e '[.resource_changes[]? | select((.change.actions | index("create")) != null or (.change.actions | index("delete")) != null)] | length == 0' >/dev/null
done

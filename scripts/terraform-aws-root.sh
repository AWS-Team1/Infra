#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "usage: $0 <plan-apply|plan-destroy|apply-destroy> <root>" >&2
  exit 2
}

ACTION=${1:-}
ROOT=${2:-}
case "$ACTION" in
  plan-apply|plan-destroy|apply-destroy) ;;
  *) usage ;;
esac

case "$ROOT" in
  persistent|aws-state-backup|aws-core|aws-rds|aws-cache|aws-ops|aws-eks|aws-eks-platform|aws-db-bootstrap) ;;
  *) echo "unsupported Terraform root: $ROOT" >&2; exit 2 ;;
esac

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BACKEND_CONFIG="$REPO_ROOT/env/backend.hcl"

terraform -chdir="$REPO_ROOT/$ROOT" init -reconfigure -backend-config="$BACKEND_CONFIG" -input=false

case "$ACTION" in
  plan-apply)
    terraform -chdir="$REPO_ROOT/$ROOT" plan -input=false -lock-timeout=5m -out=tfplan
    terraform -chdir="$REPO_ROOT/$ROOT" show -no-color tfplan

    # Normal apply must never hide a replacement or deletion.
    terraform -chdir="$REPO_ROOT/$ROOT" show -json tfplan |
      jq -e '
        [
          .resource_changes[]?
          | select((.change.actions | index("delete")) != null)
          | .address
        ] as $destructive
        | if ($destructive | length) == 0
          then true
          else error("destructive apply actions: " + ($destructive | join(", ")))
          end
      ' >/dev/null

    terraform -chdir="$REPO_ROOT/$ROOT" apply -input=false -lock-timeout=5m tfplan
    ;;
  plan-destroy)
    terraform -chdir="$REPO_ROOT/$ROOT" plan -destroy -input=false -lock-timeout=5m -out=tfplan-destroy
    terraform -chdir="$REPO_ROOT/$ROOT" show -no-color tfplan-destroy
    ;;
  apply-destroy)
    test -f "$REPO_ROOT/$ROOT/tfplan-destroy"
    terraform -chdir="$REPO_ROOT/$ROOT" apply -input=false -lock-timeout=5m tfplan-destroy
    ;;
esac

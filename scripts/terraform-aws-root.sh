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
  persistent|aws-state-backup|aws-core|aws-rds|aws-cache|aws-ops|aws-eks|aws-eks-platform|aws-db-bootstrap|aws-observability) ;;
  *) echo "unsupported Terraform root: $ROOT" >&2; exit 2 ;;
esac

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BACKEND_CONFIG="$REPO_ROOT/env/backend.hcl"

terraform -chdir="$REPO_ROOT/$ROOT" init -reconfigure -backend-config="$BACKEND_CONFIG" -input=false

case "$ACTION" in
  plan-apply)
    terraform -chdir="$REPO_ROOT/$ROOT" plan -input=false -lock-timeout=5m -out=tfplan
    terraform -chdir="$REPO_ROOT/$ROOT" show -no-color tfplan

    terraform -chdir="$REPO_ROOT/$ROOT" show -json tfplan |
      jq -r --arg root "$ROOT" '
        [.resource_changes[]? | select(.change.actions == ["create"]) | .address] as $create
        | [.resource_changes[]? | select(.change.actions == ["update"]) | .address] as $update
        | [
            .resource_changes[]?
            | select(.change.actions == ["delete"])
            | .address
          ] as $delete
        | [
            .resource_changes[]?
            | select(
                (.change.actions | index("create")) != null and
                (.change.actions | index("delete")) != null
              )
            | .address
          ] as $replace
        | (
            [
              "Terraform plan action summary for " + $root,
              "",
              "CREATE: \($create | length)",
              "UPDATE: \($update | length)",
              "DELETE: \($delete | length)",
              "REPLACE: \($replace | length)",
              "",
              "DELETE:"
            ]
            + (if ($delete | length) == 0 then ["(none)"] else ($delete | map("- " + .)) end)
            + ["", "REPLACE:"]
            + (if ($replace | length) == 0 then ["(none)"] else ($replace | map("- " + .)) end)
          )[]
      '

    destructive_root_enabled=false
    case "$ROOT" in
      aws-rds|aws-cache|aws-ops|aws-eks|aws-eks-platform|aws-db-bootstrap|aws-observability)
        destructive_root_enabled=true
        ;;
    esac

    destructive_apply_allowed=false
    if [[ ${ALLOW_DESTRUCTIVE_APPLY:-false} == "true" && "$destructive_root_enabled" == "true" ]]; then
      destructive_apply_allowed=true
    fi

    if [[ "$destructive_root_enabled" != "true" ]]; then
      block_reason="destructive Terraform apply is not allowed for protected root $ROOT"
    else
      block_reason="destructive Terraform apply requires the explicit workflow checkbox and confirmation"
    fi

    echo "Destructive apply permission for $ROOT: $destructive_apply_allowed"
    terraform -chdir="$REPO_ROOT/$ROOT" show -json tfplan |
      jq -e --arg allowed "$destructive_apply_allowed" --arg reason "$block_reason" '
        [
          .resource_changes[]?
          | select(
              .change.actions == ["delete"] or
              (
                (.change.actions | index("create")) != null and
                (.change.actions | index("delete")) != null
              )
            )
          | .address
        ] as $destructive
        | if ($destructive | length) == 0
          then true
          elif $allowed == "true"
          then true
          else error($reason + ": " + ($destructive | join(", ")))
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

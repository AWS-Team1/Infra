#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "usage: $0 <backup-directory> <terraform-root>..." >&2
  exit 2
}

BACKUP_DIR=${1:-}
shift || true
(( $# > 0 )) || usage
[[ -n "$BACKUP_DIR" ]] || usage

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BACKEND_CONFIG="$REPO_ROOT/env/backend.hcl"

mkdir -p -- "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

for root in "$@"; do
  case "$root" in
    persistent|aws-state-backup|aws-core|aws-rds|aws-cache|aws-ops|aws-eks|aws-eks-platform|aws-db-bootstrap|aws-observability|aws-infra-observability) ;;
    *) echo "unsupported Terraform backup root: $root" >&2; exit 2 ;;
  esac

  destination="$BACKUP_DIR/$root.tfstate"
  terraform -chdir="$REPO_ROOT/$root" init \
    -reconfigure \
    -backend-config="$BACKEND_CONFIG" \
    -input=false
  terraform -chdir="$REPO_ROOT/$root" state pull > "$destination"
  [[ -s "$destination" ]] || {
    echo "Terraform state backup is missing or empty for root: $root" >&2
    exit 1
  }
  chmod 600 "$destination"
  echo "Collected Terraform state for root: $root"
done

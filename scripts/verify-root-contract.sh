#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=${1:-}
case "$ROOT" in
  persistent|aws-core|aws-rds|aws-cache|aws-ops|aws-eks|aws-eks-platform|aws-db-bootstrap) ;;
  *) echo "usage: $0 <terraform-root>" >&2; exit 2 ;;
esac

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CANONICAL="$REPO_ROOT/env/backend.hcl"
EMBEDDED="$REPO_ROOT/$ROOT/backend.tf"

read_hcl_scalar() {
  local file=$1 key=$2
  awk -v wanted="$key" '
    $1 == wanted && $2 == "=" {
      value=$3
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

for key in bucket region encrypt use_lockfile; do
  expected=$(read_hcl_scalar "$CANONICAL" "$key")
  actual=$(read_hcl_scalar "$EMBEDDED" "$key")
  [[ -n "$expected" && "$actual" == "$expected" ]] || {
    echo "$ROOT backend $key mismatch: '$actual' != '$expected'" >&2
    exit 1
  }
done

grep -Fq 'source = "../env"' "$REPO_ROOT/$ROOT/environment.tf"
echo "$ROOT supports the shared GitHub Actions and Code Server contract"

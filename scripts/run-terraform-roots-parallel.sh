#!/usr/bin/env bash
# Run scripts/terraform-aws-root.sh for several independent Terraform roots at once.
#
#   run-terraform-roots-parallel.sh <plan-destroy|apply-destroy> <root> [<root> ...]
#
# Every root is validated before any child starts. Each root runs as its own
# background process with its own log file, and every child is waited for even
# after another child fails, so no Terraform run is left orphaned mid-apply.
# The script exits non-zero if any root failed.
#
# aws-core and persistent are accepted only for plan-destroy: their destroy must
# stay sequential and last, after every consumer root is gone.
set -Eeuo pipefail

usage() {
  echo "usage: $0 <plan-destroy|apply-destroy> <root> [<root> ...]" >&2
  exit 2
}

ACTION=${1:-}
case "$ACTION" in
  plan-destroy)
    allowed_roots=" aws-db-bootstrap aws-observability aws-eks-platform aws-eks aws-ops aws-cache aws-rds aws-core persistent "
    ;;
  apply-destroy)
    allowed_roots=" aws-db-bootstrap aws-observability aws-eks-platform aws-eks aws-ops aws-cache aws-rds "
    ;;
  *) usage ;;
esac
shift
(( $# > 0 )) || usage

roots=()
for root in "$@"; do
  [[ "$allowed_roots" == *" $root "* ]] || {
    echo "root not allowed for parallel $ACTION: $root" >&2
    exit 2
  }
  for seen in "${roots[@]}"; do
    [[ "$seen" != "$root" ]] || {
      echo "duplicate root: $root" >&2
      exit 2
    }
  done
  roots+=("$root")
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_SCRIPT="$SCRIPT_DIR/terraform-aws-root.sh"
[[ -f "$ROOT_SCRIPT" ]] || {
  echo "missing $ROOT_SCRIPT" >&2
  exit 2
}

log_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/tf-parallel.XXXXXX")
trap 'rm -rf "$log_dir"' EXIT

echo "[parallel] $ACTION: ${roots[*]}"

declare -A pid_of
for root in "${roots[@]}"; do
  (
    started=$(date +%s)
    if bash "$ROOT_SCRIPT" "$ACTION" "$root"; then rc=0; else rc=$?; fi
    echo "$rc $(( $(date +%s) - started ))" > "$log_dir/$root.status"
    exit "$rc"
  ) < /dev/null > "$log_dir/$root.log" 2>&1 &
  pid_of[$root]=$!
  echo "[parallel] started $root (pid ${pid_of[$root]})"
done

# Report each root as soon as it finishes. A child that died without writing its
# status file is also treated as finished; wait below still returns its exit code.
started_all=$(date +%s)
declare -A reported
while :; do
  running=()
  for root in "${roots[@]}"; do
    if [[ -f "$log_dir/$root.status" ]] || ! kill -0 "${pid_of[$root]}" 2>/dev/null; then
      if [[ -z "${reported[$root]:-}" ]]; then
        reported[$root]=1
        echo "[parallel] finished $root: $(cut -d' ' -f1 "$log_dir/$root.status" 2>/dev/null || echo '?') (exit code)"
      fi
    else
      running+=("$root")
    fi
  done
  (( ${#running[@]} == 0 )) && break
  echo "[parallel] still running after $(( $(date +%s) - started_all ))s: ${running[*]}"
  sleep "${PARALLEL_POLL_SECONDS:-30}"
done

failed=()
declare -A rc_of duration_of
for root in "${roots[@]}"; do
  if wait "${pid_of[$root]}"; then rc=0; else rc=$?; fi
  duration=$(cut -d' ' -f2 "$log_dir/$root.status" 2>/dev/null || echo '?')
  rc_of[$root]=$rc
  duration_of[$root]=$duration

  if (( rc == 0 )); then
    echo "::group::$root $ACTION OK (${duration}s)"
    cat "$log_dir/$root.log"
    echo "::endgroup::"
  else
    failed+=("$root")
    echo "::error::$root $ACTION failed with exit code $rc after ${duration}s"
    echo "----- $root log -----"
    cat "$log_dir/$root.log"
    echo "----- end $root log -----"
  fi
done

echo "[parallel] summary for $ACTION:"
for root in "${roots[@]}"; do
  rc=${rc_of[$root]}
  printf '  %-7s %-18s exit=%s %ss\n' "$( (( rc == 0 )) && echo OK || echo FAILED)" "$root" "$rc" "${duration_of[$root]}"
done

if (( ${#failed[@]} > 0 )); then
  echo "::error::$ACTION failed for: ${failed[*]}"
  exit 1
fi

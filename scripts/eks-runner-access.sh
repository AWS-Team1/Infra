#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  echo "ERROR: $*" >&2
  return 1
}

validate_name_component() {
  local value=$1
  local label=$2

  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    die "$label contains characters that are unsafe for the restore state file: $value"
}

validate_ipv4() {
  local address=$1
  local octet
  local -a octets

  [[ "$address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a octets <<<"$address"
  [[ ${#octets[@]} -eq 4 ]] || return 1

  for octet in "${octets[@]}"; do
    ((10#$octet <= 255)) || return 1
  done
}

validate_ipv4_cidr() {
  local cidr=$1
  local address prefix

  [[ "$cidr" =~ ^([^/]+)/([0-9]{1,2})$ ]] || return 1
  address=${BASH_REMATCH[1]}
  prefix=${BASH_REMATCH[2]}
  validate_ipv4 "$address" || return 1
  ((10#$prefix <= 32))
}

validate_cidr_array() {
  local cidrs=$1
  local label=$2
  local cidr

  jq -e 'type == "array" and length > 0 and all(.[]; type == "string")' <<<"$cidrs" >/dev/null ||
    die "$label must be a non-empty JSON array of IPv4 CIDR strings"

  while IFS= read -r cidr; do
    cidr=${cidr%$'\r'}
    validate_ipv4_cidr "$cidr" || die "$label contains an invalid IPv4 CIDR: $cidr"
  done < <(jq -r '.[]' <<<"$cidrs")
}

initialize_context() {
  local temp_root user_id

  REGION=${AWS_REGION:?AWS_REGION is required}
  CLUSTER=${EKS_CLUSTER_NAME:-boa-eks}
  validate_name_component "$REGION" "AWS region"
  validate_name_component "$CLUSTER" "EKS cluster name"

  if [[ -n ${RUNNER_TEMP:-} ]]; then
    temp_root=$RUNNER_TEMP
    STATE_DIR="$temp_root/eks-runner-access-state"
  else
    temp_root=${TMPDIR:-/tmp}
    user_id=${UID:-$(id -u)}
    STATE_DIR="$temp_root/eks-runner-access-state-$user_id"
  fi
  [[ -n "$temp_root" ]] || die "no safe temporary directory is available"

  [[ ! -L "$STATE_DIR" ]] || die "restore state directory must not be a symbolic link: $STATE_DIR"
  mkdir -p -- "$STATE_DIR"
  chmod 700 -- "$STATE_DIR"
  STATE_FILE="$STATE_DIR/eks-runner-access-${REGION}-${CLUSTER}.json"
  [[ ! -L "$STATE_FILE" ]] || die "restore state file must not be a symbolic link: $STATE_FILE"
}

describe_cluster() {
  local output

  if output=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" --output json 2>&1); then
    CLUSTER_JSON=$output
    return 0
  fi

  if grep -q 'ResourceNotFoundException' <<<"$output"; then
    return 3
  fi

  echo "ERROR: unable to describe EKS cluster $CLUSTER in $REGION" >&2
  echo "$output" >&2
  return 1
}

ensure_cluster_or_noop() {
  local status

  if describe_cluster; then
    return 0
  else
    status=$?
  fi

  if [[ $status -eq 3 ]]; then
    echo "EKS cluster $CLUSTER is absent; runner access step is a no-op."
    return 3
  fi

  return "$status"
}

validate_state_file() {
  local state=$1

  jq -e '
    type == "object" and
    (.region | type == "string") and
    (.cluster | type == "string") and
    (.original_public_access_cidrs | type == "array") and
    (.grant_applied | type == "boolean")
  ' <<<"$state" >/dev/null || die "restore state file is malformed: $STATE_FILE"

  [[ $(jq -r '.region' <<<"$state") == "$REGION" ]] ||
    die "restore state region does not match current region: $STATE_FILE"
  [[ $(jq -r '.cluster' <<<"$state") == "$CLUSTER" ]] ||
    die "restore state cluster does not match current cluster: $STATE_FILE"
}

write_state_file() {
  local original_cidrs=$1
  local grant_applied=$2
  local content temp_file

  content=$(jq -cn \
    --arg region "$REGION" \
    --arg cluster "$CLUSTER" \
    --argjson cidrs "$original_cidrs" \
    --argjson grant_applied "$grant_applied" \
    '{region:$region, cluster:$cluster, original_public_access_cidrs:$cidrs, grant_applied:$grant_applied}')

  umask 077
  temp_file=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
  printf '%s\n' "$content" >"$temp_file"
  chmod 600 -- "$temp_file"
  mv -f -- "$temp_file" "$STATE_FILE"
}

wait_for_update() {
  local update_id=$1
  local timeout_seconds=${EKS_UPDATE_TIMEOUT_SECONDS:-600}
  local poll_seconds=${EKS_UPDATE_POLL_SECONDS:-10}
  local deadline status

  [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die "EKS_UPDATE_TIMEOUT_SECONDS must be a positive integer"
  [[ "$poll_seconds" =~ ^[1-9][0-9]*$ ]] || die "EKS_UPDATE_POLL_SECONDS must be a positive integer"
  deadline=$((SECONDS + timeout_seconds))

  while ((SECONDS < deadline)); do
    status=$(aws eks describe-update \
      --region "$REGION" \
      --name "$CLUSTER" \
      --update-id "$update_id" \
      --query 'update.status' \
      --output text)

    case "$status" in
      Successful) break ;;
      Failed|Cancelled)
        die "EKS cluster configuration update $update_id ended with status $status"
        ;;
      InProgress) sleep "$poll_seconds" ;;
      *) die "EKS cluster configuration update $update_id returned unexpected status: $status" ;;
    esac
  done

  [[ ${status:-} == "Successful" ]] || die "timed out waiting for EKS cluster configuration update $update_id"
  aws eks wait cluster-active --region "$REGION" --name "$CLUSTER"
}

update_public_access_cidrs() {
  local cidrs=$1
  local config update_response update_id

  validate_cidr_array "$cidrs" "EKS public access CIDRs"
  config=$(jq -cn --argjson cidrs "$cidrs" '{publicAccessCidrs:$cidrs}')
  update_response=$(aws eks update-cluster-config \
    --region "$REGION" \
    --name "$CLUSTER" \
    --resources-vpc-config "$config" \
    --output json)
  update_id=$(jq -er '.update.id | select(type == "string" and length > 0)' <<<"$update_response") ||
    die "EKS update-cluster-config did not return an update ID"
  wait_for_update "$update_id"
}

grant_runner_access() {
  local original_cidrs runner_ip granted_cidrs existing_state status

  if ensure_cluster_or_noop; then
    :
  else
    status=$?
    [[ $status -eq 3 ]] && return 0
    return "$status"
  fi

  original_cidrs=$(jq -ce '.cluster.resourcesVpcConfig.publicAccessCidrs' <<<"$CLUSTER_JSON") ||
    die "EKS describe-cluster did not return valid publicAccessCidrs"
  validate_cidr_array "$original_cidrs" "live EKS publicAccessCidrs"

  if [[ -f "$STATE_FILE" ]]; then
    existing_state=$(<"$STATE_FILE")
    validate_state_file "$existing_state"
    if [[ $(jq -r '.grant_applied' <<<"$existing_state") == "true" ]]; then
      die "temporary runner access is already marked as applied; restore it before granting again"
    fi
  fi

  write_state_file "$original_cidrs" false

  runner_ip=${RUNNER_PUBLIC_IP:-$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')}
  validate_ipv4 "$runner_ip" || die "runner public IP is not a valid IPv4 address: $runner_ip"

  granted_cidrs=$(jq -cn \
    --argjson original "$original_cidrs" \
    --arg runner "$runner_ip/32" \
    '$original + [$runner] | reduce .[] as $cidr ([]; if index($cidr) then . else . + [$cidr] end)')
  update_public_access_cidrs "$granted_cidrs"
  write_state_file "$original_cidrs" true

  echo "grant EKS runner access: $granted_cidrs"
}

restore_runner_access() {
  local state original_cidrs status

  if ensure_cluster_or_noop; then
    :
  else
    status=$?
    [[ $status -eq 3 ]] && return 0
    return "$status"
  fi

  if [[ ! -f "$STATE_FILE" ]]; then
    echo "temporary runner access was not applied; restore is a no-op."
    return 0
  fi

  state=$(<"$STATE_FILE")
  validate_state_file "$state"

  if [[ $(jq -r '.grant_applied' <<<"$state") != "true" ]]; then
    echo "temporary runner access was not applied; restore is a no-op."
    return 0
  fi

  original_cidrs=$(jq -ce '.original_public_access_cidrs' <<<"$state") ||
    die "restore state file does not contain valid original public access CIDRs"
  validate_cidr_array "$original_cidrs" "saved EKS publicAccessCidrs"
  update_public_access_cidrs "$original_cidrs"
  rm -f -- "$STATE_FILE"

  echo "restore EKS runner access: $original_cidrs"
}

main() {
  local action=${1:-}

  case "$action" in
    grant|restore) ;;
    *) echo "usage: $0 <grant|restore>" >&2; return 2 ;;
  esac

  initialize_context

  case "$action" in
    grant) grant_runner_access ;;
    restore) restore_runner_access ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi

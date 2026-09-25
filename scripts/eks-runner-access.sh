#!/usr/bin/env bash
set -Eeuo pipefail

ACTION=${1:-}
case "$ACTION" in
  grant|restore) ;;
  *) echo "usage: $0 <grant|restore>" >&2; exit 2 ;;
esac

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REGION=${AWS_REGION:?AWS_REGION is required}
CLUSTER=${EKS_CLUSTER_NAME:-boa-eks}

if ! aws eks describe-cluster --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1; then
  echo "EKS cluster $CLUSTER is absent; runner access step is a no-op."
  exit 0
fi

terraform -chdir="$REPO_ROOT/aws-eks" init -reconfigure -backend-config="$REPO_ROOT/env/backend.hcl" -input=false >/dev/null

BASELINE=$(terraform -chdir="$REPO_ROOT/aws-eks" output -json baseline_public_access_cidrs)
jq -e 'type == "array" and length > 0 and all(.[]; test("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$"))' <<<"$BASELINE" >/dev/null

if [[ "$ACTION" == grant ]]; then
  RUNNER_IP=${RUNNER_PUBLIC_IP:-$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')}
  [[ "$RUNNER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
  CIDRS=$(jq -cn --argjson baseline "$BASELINE" --arg runner "$RUNNER_IP/32" '$baseline + [$runner] | unique')
else
  CIDRS=$BASELINE
fi

CONFIG=$(jq -cn --argjson cidrs "$CIDRS" '{endpointPublicAccess:true,publicAccessCidrs:$cidrs}')
aws eks update-cluster-config --region "$REGION" --name "$CLUSTER" --resources-vpc-config "$CONFIG" >/dev/null
aws eks wait cluster-active --region "$REGION" --name "$CLUSTER"
echo "$ACTION EKS runner access: $CIDRS"

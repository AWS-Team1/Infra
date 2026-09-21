#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
namespace="bank-of-anthos"

for command_name in jq kubectl terraform; do
  command -v "$command_name" >/dev/null || {
    echo "ERROR: 필수 명령 없음: $command_name" >&2
    exit 1
  }
done

cache_endpoint="$(terraform -chdir="$script_dir/../aws-test-cache" output -raw cache_endpoint_address)"

runtime_patch="$(jq -nc --arg endpoint "$cache_endpoint" '{data:{VALKEY_HOST:$endpoint}}')"
kubectl --namespace "$namespace" patch configmap bank-of-anthos-env --type merge --patch "$runtime_patch"

for deployment_name in frontend userservice contacts balancereader ledgerwriter transactionhistory; do
  if kubectl --namespace "$namespace" get deployment "$deployment_name" >/dev/null 2>&1; then
    kubectl --namespace "$namespace" rollout restart deployment "$deployment_name"
  fi
done

unset cache_endpoint runtime_patch
echo "테스트 애플리케이션에 실제 ElastiCache TLS endpoint를 반영했습니다."

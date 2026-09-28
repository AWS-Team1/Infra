## 변경 목적

<!-- 이 변경이 필요한 이유와 해결하려는 문제를 적는다. -->

## 승격 대상 브랜치 확인

- [ ] `feature/*` → `dev`
- [ ] `dev` → `release`
- [ ] `release` → `main`
- [ ] 위 허용 방향 외의 PR이 아님을 확인했다 (`Branch Promotion Policy` Check)

## 변경 Root

<!-- 변경한 Terraform root를 모두 체크하거나 추가한다. -->

- [ ] persistent
- [ ] aws-state-backup
- [ ] aws-core
- [ ] aws-rds
- [ ] aws-cache
- [ ] aws-ops
- [ ] aws-eks
- [ ] aws-eks-platform
- [ ] aws-db-bootstrap
- [ ] aws-observability
- [ ] aws-infra-observability
- [ ] gcp-* / net-link / 기타: <!-- root 이름 -->
- [ ] Terraform root 변경 없음 (workflow, scripts, docs만 변경)

## Terraform fmt / validate 결과

- [ ] `terraform fmt -check -recursive` 통과
- [ ] 변경 root의 `terraform init -backend=false` / `terraform validate` 통과
- [ ] `Terraform CI Summary` Check 성공

## 예상 Plan 요약

<!-- PR CI는 plan을 실행하지 않는다. 로컬 또는 Code Server에서 확인한 plan 요약을 적는다. -->

| Root | Create | Change | Destroy | Replace 대상 |
|---|---:|---:|---:|---|
| | | | | |

- [ ] 예상하지 못한 Destroy / Replace가 없다 (있다면 아래에 사유를 적는다)

## State 영향

- [ ] State 변경 없음
- [ ] `state mv` / `state rm` / `import` 필요 (대상 주소와 실행 순서를 적는다)
- [ ] Backend key 또는 root 구조 변경

## 보안 / IAM / Network 영향

- [ ] 영향 없음
- [ ] IAM 권한 추가 또는 확장 (대상 Role·Policy와 사유)
- [ ] Security Group / NACL / Route / DNS 변경
- [ ] Secret·자격증명 관련 변경 (값은 PR에 적지 않는다)

## 롤백 방법

<!-- 이전 커밋으로 되돌려 apply, 리소스 수동 복구, state 백업 복원 등 구체적으로 적는다. -->

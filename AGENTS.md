# AI 작업 가이드

이 문서는 이 저장소에서 AI 코딩 에이전트(Claude Code, Codex, Cursor 등 무엇이든)가
따라야 하는 공통 규칙이다. 사람이 직접 작업할 때도 참고할 수 있다.

## 이 저장소가 하는 일

Terraform으로 AWS·GCP에 Bank of Anthos(`boa`) 데모용 인프라를 구성하는 IaC 저장소다.
최상위에 실행 가능한 `.tf`는 없다. `<provider>-<component>/` 디렉터리 하나하나가
독립된 backend·state를 가진 Terraform root다.

```
aws-modules/, gcp-modules/, net-modules/   재사용 모듈 (backend 없음)
aws-core, aws-eks, aws-rds, aws-cache,
aws-ops, aws-db-bootstrap, aws-dms          AWS 쪽 root
gcp-core, gcp-gke, gcp-cloudsql, gcp-ops    GCP 쪽 root (AWS 구성 미러)
net-link                                    AWS↔GCP VPN 연결 (DR)
boa/k8s                                     참고용 K8s manifest (배포 소스는 별도 GitOps 저장소)
docs/                                       설계 문서 · 런북
```

각 root는 같은 S3 버킷(`boa-terraform-state-6416`)에 서로 다른 state key로 저장된다.
자세한 구조·기본값·apply 순서는 `README.md`를 따른다.

## 절대 규칙

1. **`terraform apply` / `terraform destroy`는 사용자가 그 자리에서 명시적으로 지시한
   경우에만 실행한다.** 이 저장소의 state는 실제로 돈이 드는 AWS/GCP 리소스를 가리킨다.
   `terraform plan`, `validate`, `fmt`처럼 상태를 바꾸지 않는 명령은 자유롭게 사용해도 된다.
2. **`terraform state rm/mv/import` 등 state를 직접 조작하는 명령은 사용자가 명시적으로
   요청한 경우에만 실행한다.** 이미 지시받아 수행한 state 변경을 스스로 되돌리거나
   다시 만지지 않는다.
3. **`.github/workflows/terraform-aws-destroy.yml`은 실제 AWS 인프라 전체를 삭제하는
   workflow다.** workflow_dispatch를 직접 트리거하지 않는다. `confirm_destroy` /
   `confirmation_text` 가드나 DMS/VPN 차단 로직 같은 안전장치를 약화시키는 수정을
   하지 않는다.
4. **ECR(`boa-frontend`, `boa-userservice`, `boa-contacts`, `boa-balancereader`,
   `boa-ledgerwriter`, `boa-transactionhistory`)은 Terraform이 관리하지 않는다.**
   2026-09에 `module.ecr`을 `aws-ops`와 state에서 의도적으로 제거하고 콘솔 수동 관리로
   전환했다. `aws-modules/ecr`는 미사용 모듈로 남아 있을 뿐이며, 별도 지시 없이 다시
   연결하지 않는다.
5. **GitOps 저장소, Kubernetes workload manifest, CI가 참조하는 ECR 이미지 경로는 이
   저장소의 작업 범위가 아니다.** Terraform 쪽 변경을 이유로 이런 파일들을 함께
   고치지 않는다.
6. **backend(S3) 접근 없이 문법만 확인할 때는**
   `terraform -chdir=<root> init -backend=false && terraform validate`를 쓴다.
   로컬 AWS 자격증명이 이 프로젝트 계정이 아닌 다른 계정으로 잡혀 있을 수 있으니,
   실제 backend로 `init -reconfigure`를 시도하기 전에 `aws sts get-caller-identity`로
   계정을 먼저 확인한다.
7. 로컬 검증(`init -backend=false` 등)으로 생긴 `.terraform/`, `.terraform.lock.hcl`
   변경은 커밋 전에 되돌린다. provider 마이너 버전이 의도치 않게 bump되어 diff에
   섞여 들어갈 수 있다.
8. **git add는 파일을 지정해서 한다** (`git add -A`/`git add .` 금지). 커밋 전에는
   `git status`로 포함된 내용을 확인한다.

## 자주 쓰는 검증 명령

```
terraform fmt -recursive
terraform -chdir=<root> init -backend=false
terraform -chdir=<root> validate
```

## 참고

- 전체 구조·기본값·apply/destroy 순서: `README.md`
- root 분리 설계 배경: `docs/specs/2026-09-14-terraform-root-split-design.md`
- AWS 전체 삭제 절차: `docs/AWS_TEARDOWN_RUNBOOK.md` (ECR 관련 서술은 2026-09 변경 이전 내용이 일부 남아 있을 수 있음 — 이 문서의 4번 규칙이 우선한다)

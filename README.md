# AWS Infrastructure with Terraform

Terraform으로 AWS 서울 리전(`ap-northeast-2`)의 VPC, EKS, PostgreSQL RDS,
Serverless Valkey와 운영용 ALB, Tokyo 리전(`ap-northeast-1`)의 DR state backup S3를
관리합니다. 저장소 최상위에는 실행 대상 `.tf`가 없으며, 독립된 Terraform root와
재사용 모듈로 구성됩니다.

## 수명주기 구조

| root | state key | 소유 범위 | provider | 의존 |
|---|---|---|---|---|
| `persistent` | `aws/persistent/terraform.tfstate` | JWT·애플리케이션 DB 장기 보존 Secret | aws · random | — |
| `aws-state-backup` | `aws/state-backup/terraform.tfstate` | Tokyo DR state backup S3 | aws | 기존 GitHub Terraform OIDC Role 조회 |
| `aws-core` | `aws/core/terraform.tfstate` | VPC·Subnet·NAT | aws | — |
| `aws-rds` | `aws/rds/terraform.tfstate` | PostgreSQL RDS | aws | core |
| `aws-cache` | `aws/cache/terraform.tfstate` | Serverless Valkey | aws · random | core |
| `aws-ops` | `aws/ops/terraform.tfstate` | 운영 ALB | aws | core |
| `aws-eks` | `aws/eks/terraform.tfstate` | EKS·IAM·Add-on·Pod Identity | aws | core |
| `aws-eks-platform` | `aws/eks-platform/terraform.tfstate` | AWS Load Balancer Controller Helm/SA·CSI RBAC | kubernetes · helm | core · eks |
| `aws-db-bootstrap` | `aws/db-bootstrap/terraform.tfstate` | DB bootstrap IAM·Pod Identity | aws | eks · rds · persistent Secret 조회 |

비민감 공통 입력은 local module인 `env/main.tf`가 단일 기준입니다. 모든 root가 이
모듈을 직접 읽으므로 GitHub Actions와 Code Server의 일반 `terraform apply`가 같은 값을
사용합니다. S3 backend는 `boa-terraform-state-6416` 버킷과 `use_lockfile = true`를
사용합니다. Terraform backend는 module 값을 참조할 수 없으므로 각 `backend.tf`에
Code Server bootstrap 값을 포함하고, CI는 동일한 `env/backend.hcl`을 명시적으로 전달합니다.

## 적용 및 삭제 순서

정상 적용 순서:

```text
persistent → aws-state-backup → aws-core → aws-rds → aws-cache → aws-ops → aws-eks
→ 임시 CI runner CIDR 허용 → aws-eks-platform → aws-db-bootstrap → 기준 CIDR 복원
→ Terraform state DR backup
```

정상 삭제 순서:

```text
명시적 Destroy 확인 → AWS 계정 확인 → DMS/VPN 기반 destroy_core 판정
→ 임시 CI runner CIDR 허용
→ EKS external pre-clean
  (Argo CD reconciliation 정지 → 프로젝트 Ingress/TargetGroupBinding 삭제
   → Karpenter NodePool 삭제 → NodeClaim 종료 대기 → EC2NodeClass 삭제
   → controller가 생성한 ALB/Target Group/Security Group/ENI/EC2/Instance Profile 정리 대기)
→ 전체 root destroy plan 사전 검증
→ aws-db-bootstrap → aws-eks-platform → aws-eks → aws-ops
→ aws-cache → aws-rds → aws-core(DMS/VPN dependency가 없을 때만)
→ persistent(full_teardown=true만)
→ 삭제 결과 검증 → 클러스터가 남아 있으면 기준 CIDR 복원
```

GitHub Actions의 AWS Apply는 위 Terraform root와 state만 관리합니다. GitOps repository
checkout, runtime render, generated manifest commit/push, Argo CD bootstrap·Root Application·
Application sync, Karpenter 및 application 배포는 워크플로에 포함하지 않습니다. 이 작업은
Code Server 또는 별도의 관리 절차에서 수동으로 수행합니다.

Destroy의 `EKS external pre-clean`은 GitOps 배포 자동화가 아니라, 이미 live Kubernetes
API에 존재하는 이 프로젝트 소유 resource와 controller-owned AWS dependency를 Terraform
destroy 전에 안전하게 제거하는 teardown-only 단계입니다. GitOps repository는 사용하지 않으며,
정확한 name/namespace/label/tag로 식별된 resource만 삭제·대기합니다. dependency가 제한 시간
안에 사라지지 않으면 `aws-eks-platform` destroy 전에 중단합니다.

`aws-eks-platform`은 GitOps workload가 아니라 Terraform이 소유하는 LBC Helm/ServiceAccount와
CSI RBAC root이므로 Apply/Destroy 수명주기에 계속 포함합니다.

`persistent`는 일반 삭제에서 제외합니다. Secret까지 포함한 전체 폐기 의도가 명시된 경우에만
별도 `full_teardown` 입력으로 마지막에 삭제합니다. ECR은 이 저장소의 Terraform
적용·삭제 수명주기에 포함하지 않습니다.

`aws-state-backup`도 routine Destroy와 `full_teardown` 모두에서 제외합니다. Backup bucket은
`force_destroy = false`와 `prevent_destroy = true`로 보호합니다. 명시적으로 폐기하려면 먼저
백업 보존 여부를 결정하고 `prevent_destroy`를 코드에서 해제한 뒤, 별도 승인 절차로 이 root만
삭제해야 합니다. Lifecycle expiration은 보존 정책이 정해지지 않아 구성하지 않습니다.

## Terraform state DR backup

기존 Terraform backend는 서울 리전의 `boa-terraform-state-6416`을 그대로 사용합니다.
`aws-state-backup` root 자체의 state도 이 primary backend의
`aws/state-backup/terraform.tfstate`에 저장합니다. Tokyo 리전의
`boa-terraform-state-backup-769413326616-ap-northeast-1`은 backend가 아니라 Apply 성공 후
생성되는 state 사본만 저장하는 DR destination입니다.

Apply workflow는 모든 Terraform root 적용이 성공한 실제 Apply에서만 별도 runner의
`backup-state` job을 실행합니다. `scripts/collect-terraform-state-backup.sh`는 기존 backend를
초기화하고 각 root에 `terraform state pull`을 실행해 권한이 제한된 임시 디렉터리에 state만
수집합니다. `scripts/upload-terraform-state-backup-s3.sh`는 완성된 backup directory를 받아
S3 업로드와 object 크기·S3 SHA-256 checksum 검증만 담당합니다. 따라서 향후 Backup Server로
전환할 때는 수집 로직과 root 목록을 유지하고 upload adapter 호출만 교체할 수 있습니다.

각 backup set은 다음처럼 기존 데이터를 덮어쓰지 않는 key를 사용합니다.

```text
terraform-state-backups/20260926T051500Z/<github-sha>/
├── metadata.json
├── SHA256SUMS
├── persistent.tfstate
├── aws-state-backup.tfstate
├── aws-core.tfstate
├── aws-rds.tfstate
├── aws-cache.tfstate
├── aws-ops.tfstate
├── aws-eks.tfstate
├── aws-eks-platform.tfstate
└── aws-db-bootstrap.tfstate
```

`metadata.json`에는 UTC timestamp, GitHub SHA/run ID/ref, AWS account ID, source repository와
root 목록만 기록하며 state 본문이나 Secret 값은 넣지 않습니다. State는 GitHub Artifact나
Git에 업로드하지 않고 job 성공·실패와 관계없이 runner의 임시 디렉터리에서 제거합니다.
Bucket은 public access 전면 차단, versioning, Bucket owner enforced, SSE-S3(AES256), HTTPS
강제 정책을 사용합니다. 기존 `boa-github-terraform-dev` Role은 이 저장소에서 소유하지 않고
bucket policy principal로만 참조하며, backup prefix에 `s3:GetObject`, `s3:PutObject`와 bucket의
`s3:GetBucketLocation`만 허용합니다. `s3:DeleteObject`와 `s3:DeleteObjectVersion`은 명시적으로
거부합니다.

## 로컬 실행

Code Server와 GitHub Actions는 같은 root 구성을 사용합니다. 최초 clone이나 backend
변경 후 `terraform init`을 한 번 실행하면 일반 `terraform plan`과 `terraform apply`를
추가 변수 인자 없이 사용할 수 있습니다.

Code Server에서 AWS 자격 증명을 확인하고 대상 root로 이동하는 예:

```bash
aws sts get-caller-identity
cd aws-core
terraform init
terraform plan
terraform apply
```

저장소 최상위에서 실행하려면 다음처럼 `-chdir`를 사용할 수 있습니다.

```bash
terraform -chdir=<root> init -backend-config=../env/backend.hcl
terraform -chdir=<root> plan
terraform -chdir=<root> apply
```

기존 환경에서는 최초 1회 state migration을 완료하기 전까지 `persistent`와
`aws-eks-platform`에 `apply`하면 안 됩니다. 빈 destination state가 기존 physical
resource를 새로 만들려고 하기 때문입니다.

적용/삭제 자동화는 `scripts/terraform-aws-root.sh`를 사용합니다. 일반 apply 전에 저장된
plan JSON을 검사하여 delete 또는 replace가 있으면 중단합니다.

```bash
scripts/terraform-aws-root.sh plan-apply <root>
scripts/terraform-aws-root.sh plan-destroy <root>
scripts/terraform-aws-root.sh apply-destroy <root>
```

EKS API의 CI runner 접근은 `scripts/eks-runner-access.sh grant|restore`로 명시적으로
허용하고 항상 기준 CIDR로 복원합니다. Terraform `null_resource`나 `local-exec`으로
외부 런타임 동작을 숨기지 않습니다.
GitHub Actions는 OIDC Role을 사용하고 Code Server는 EC2 instance role을 사용하지만,
EKS access entry에는 두 실행 주체를 모두 Cluster Admin으로 유지합니다.
GitHub 환경에는 Terraform 실행용 `AWS_ROLE_ARN`, `AWS_REGION` variable만 필요하며,
`GITOPS_TOKEN`, `ARGOCD_REPO_USERNAME`, `ARGOCD_REPO_PASSWORD`는 AWS Terraform
워크플로에서 사용하지 않습니다.

## 검증

backend 접속 없이 정적 검증할 수 있습니다.

```bash
terraform fmt -recursive -check
terraform -chdir=<root> init -backend=false
terraform -chdir=<root> validate
```

기존 state를 새 수명주기 root로 옮기는 최초 1회 절차는
`docs/plans/2026-09-25-aws-terraform-relifecycle-migration.md`를 따릅니다.
`scripts/migrate-aws-relifecycle-state.sh`는 기본적으로 정확한 명령만 출력하며,
실행 모드는 이중 확인과 사전 state backup을 요구합니다.

## 주요 기본값과 주의사항

- Region: `ap-northeast-2`
- EKS: Kubernetes `1.36`, `t3.large` On-Demand 기본 노드 2대
- RDS: PostgreSQL 16.14, `db.t4g.micro`, Multi-AZ
- Cache: Serverless Valkey, 최대 1GB / 1,000 ECPU/s
- NAT Gateway 2개, EKS, Multi-AZ RDS, ElastiCache는 실행 중 비용이 발생합니다.
- `terraform.tfvars`, `.terraform/`, `*.tfstate`는 커밋하지 않습니다.
- 장기 보존 Secret과 state migration 전에는 migration 문서의 backup·import·source cleanup
  순서와 physical ID를 다시 확인합니다.

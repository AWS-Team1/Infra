# AWS Infrastructure with Terraform

Terraform을 사용해 AWS 서울 리전(`ap-northeast-2`)에 VPC, EKS, PostgreSQL RDS,
ElastiCache Serverless Valkey와 운영용 ALB를 구성하는 프로젝트입니다. 저장소 최상위에는
`.tf` 파일이 없고 재사용 모듈과 독립된 root로 나뉩니다.

## 디렉터리 구조

```text
.
├── aws-modules/                재사용 모듈. backend 없음, .terraform.lock.hcl 추적 안 함
│   ├── network/                기존 VPC / Public·Private·DB·Cache Subnet / NAT
│   ├── eks-iam/                IAM 역할·정책·부착 (클러스터 미참조)
│   ├── eks/                    EKS Cluster / Managed Node Group / Add-ons / Pod Identity / Access Entry
│   ├── rds/                    PostgreSQL RDS / Subnet·Parameter Group / 보안 그룹 / 모니터링 IAM·로그
│   ├── elasticache/            Serverless Valkey / RBAC User / 보안 그룹 / Secrets Manager 비밀번호
│   └── aws-load-balancer-controller/   IAM · ServiceAccount · helm_release
├── aws-core/                   루트 — network
├── aws-eks/                    루트 — eks-iam · eks · aws-load-balancer-controller
├── aws-rds/                    루트 — rds
├── aws-cache/                  루트 — elasticache
├── aws-ops/                    루트 — ECR · ops ALB
├── aws-db-bootstrap/           루트 — DB Secret · bootstrap IAM/Pod Identity
└── docs/specs/                 설계 문서
```

각 root는 독립된 backend와 state를 사용합니다. `aws-eks`는 추가로
`variables.tf`(`code_server_role_arn`) · `rbac.tf` · `terraform.tfvars`(.gitignore)를 가집니다.

## 구성 개요

- Network(`aws-core`): 기존 VPC를 재사용하고 2개 가용 영역의 Public, Private, DB, Cache Subnet을 관리합니다. Private Subnet은 가용 영역별 NAT Gateway를 사용합니다.
- EKS(`aws-eks`): Private Subnet에 Kubernetes 클러스터와 Managed Node Group을 생성합니다. VPC CNI, CoreDNS, kube-proxy, EBS CSI, Pod Identity Agent 애드온과 AWS Load Balancer Controller를 함께 설치합니다. IAM은 `eks-iam` 모듈이 별도로 담당합니다(클러스터 미참조 — [설계 문서 §6](docs/specs/2026-09-14-terraform-root-split-design.md) 참조).
- RDS(`aws-rds`): DB Subnet에 암호화된 PostgreSQL Multi-AZ 인스턴스를 생성합니다. 인바운드 5432는 EKS 클러스터 보안 그룹이 아니라 **프라이빗 서브넷 CIDR**로 허용합니다(`aws-rds`가 `aws-eks`를 몰라도 되게 하는 설계 — 설계 문서 결정 3). Master 비밀번호는 AWS Secrets Manager에서 관리하고 백업·Performance Insights·Enhanced Monitoring을 활성화합니다.
- ElastiCache(`aws-cache`): Private Subnet에 Serverless Valkey 캐시를 생성합니다. 접속 비밀번호는 무작위로 생성해 Secrets Manager에 저장하고 RBAC 사용자 그룹에 연결합니다.
- State: 루트마다 별도 state key로 같은 S3 Bucket에 암호화 저장하며, `use_lockfile`(S3 네이티브 락)로 동시 실행을 방지합니다. 자세한 내용은 아래 "루트 구조" 절을 참조하세요.

## 주요 기본값

| 항목 | 설정 |
| --- | --- |
| AWS Region | `ap-northeast-2` |
| VPC | 기존 `vpc-07194d5f908bac7cf` 재사용, CIDR `192.168.0.0/16` |
| Subnet CIDR | public `192.168.2.0/24` `192.168.3.0/24` · private `192.168.8.0/24` `192.168.9.0/24` · db `192.168.16.0/24` `192.168.17.0/24` |
| EKS Version | `1.36` |
| EKS Node | `t3.medium`, On-Demand, 2대 |
| RDS | PostgreSQL 16.14, `db.t4g.micro`, Multi-AZ |
| ElastiCache | Serverless Valkey, 최대 1GB / 1,000 ECPU/s |

## 사전 준비

- Terraform 1.11 이상
- AWS 리소스를 생성할 수 있는 자격 증명
- State 저장용 S3 Bucket `boa-terraform-state-6416` (아래 "루트 구조" 절 참조)
- EKS 관리자 권한을 연결할 IAM Role ARN

`aws-eks/terraform.tfvars`에 EKS 접근용 Role ARN을 설정합니다. 이 파일은 `.gitignore`에 포함되어 Git에 올라가지 않습니다.

```hcl
code_server_role_arn = "arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>"
```

## 실행 방법

저장소 최상위에는 실행할 `.tf`가 없습니다. `aws-core` → `aws-rds` → `aws-cache` →
`aws-eks` → `aws-ops` → `aws-db-bootstrap` 순서로 각 root를 실행합니다.

## 주의사항

- `aws-eks/main.tf`의 `public_access_cidrs`는 EKS API 접근을 허용할 공인 IP로 변경해야 합니다.
- S3 Backend Bucket은 `terraform init` 전에 별도로 생성되어 있어야 합니다.
- `terraform.tfvars`, `.terraform/`, `*.tfstate`는 민감정보 보호를 위해 커밋하지 않습니다.
- NAT Gateway 2개, EKS, Multi-AZ RDS, ElastiCache는 실행 중 비용이 발생합니다. 테스트가 끝나면 불필요한 리소스를 정리하세요.
- 현재 RDS의 `skip_final_snapshot`과 `apply_immediately` 설정은 테스트 환경에 맞춰져 있습니다. 운영 환경에서는 삭제 방지와 최종 Snapshot 정책을 검토하세요.

## 루트 구조

| 루트 | state key | provider | 의존 |
|---|---|---|---|
| `aws-core` | `aws/core/terraform.tfstate` | aws | — |
| `aws-eks` | `aws/eks/terraform.tfstate` | aws · kubernetes · helm | core |
| `aws-rds` | `aws/rds/terraform.tfstate` | aws | core |
| `aws-cache` | `aws/cache/terraform.tfstate` | aws | core |
| `aws-ops` | `aws/ops/terraform.tfstate` | aws | core |
| `aws-db-bootstrap` | `aws/db-bootstrap/terraform.tfstate` | aws | eks · rds |

`aws-ops` 는 ECR 과 ops ALB 를 갖는다. ALB 가 VPC·퍼블릭 서브넷을 필요로 하므로 core 를 읽는다.

버킷은 `boa-terraform-state-6416` (ap-northeast-2). `use_lockfile = true` 라
락 객체가 `<key>.tflock` 으로 key 마다 따로 생긴다. DynamoDB 테이블은 쓰지 않는다.

### 검증 (backend 접속 없음)

    terraform -chdir=<루트> init -backend=false
    terraform -chdir=<루트> validate
    terraform fmt -recursive -check

### apply

`aws-core`를 먼저 적용한다. `aws-rds` · `aws-cache` · `aws-eks` · `aws-ops`를
그 뒤 적용하고, 마지막으로 `aws-db-bootstrap`을 적용한다.
`aws-eks` 는 `terraform.tfvars` 의 `code_server_role_arn` 이 필요하다 (저장소에 없음).

`aws-db-bootstrap`의 `HARD-CODED` 주석은 다른 계정·리전에 재사용할 때 반드시 확인한다.
상세 순서는 GitOps 저장소의 `docs/EKS_GITOPS_CICD_RUNBOOK.md`를 따른다.

### 삭제 순서

Ingress 가 만든 ALB 는 Terraform state 에 없다. 먼저 치우지 않으면
`aws-core` destroy 가 `DependencyViolation` 으로 막힌다.

    1. kubectl delete ingress ...
    2. ALB · SG · 대상 그룹 소멸 확인
    3. terraform -chdir=aws-eks destroy
    4. terraform -chdir=aws-core destroy

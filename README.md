# AWS Infrastructure with Terraform

Terraform을 사용해 AWS 서울 리전(`ap-northeast-2`)에 VPC, EKS, PostgreSQL RDS, ElastiCache Serverless Valkey를 구성하는 프로젝트입니다.

## 디렉터리 구조

```text
.
├── backend.tf                 # Terraform State를 저장할 S3 Backend 설정
├── provider.tf                # AWS Provider 및 기본 리전 설정
├── versions.tf                # Terraform, AWS/Random Provider 버전 제약
├── main.tf                    # 전체 모듈 연결 및 인프라 기본값 정의
├── variables.tf               # 루트 입력 변수 정의
├── terraform.tfvars           # 환경별 변수 값 (Git 제외)
├── .terraform.lock.hcl        # Provider 의존성 버전 고정
└── modules/
    ├── network/               # VPC / Public·Private·DB Subnet / IGW / NAT / Route Table
    ├── security/              # ALB / RDS / ElastiCache용 Security Group 및 접근 규칙
    ├── eks/                   # EKS Cluster / Managed Node Group / IAM / Add-ons / Access Entry
    ├── rds/                   # PostgreSQL RDS / Subnet·Parameter Group / 모니터링 IAM·로그
    └── elasticache/           # Serverless Valkey / RBAC User / Secrets Manager 비밀번호
```

각 모듈의 `variables.tf`는 입력값, `outputs.tf`는 다른 모듈에서 참조하거나 배포 후 확인할 값을 정의합니다.

## 구성 개요

- Network: 2개 가용 영역(`ap-northeast-2a`, `ap-northeast-2c`)에 Public, Private, DB Subnet을 구성합니다. Private Subnet은 가용 영역별 NAT Gateway를 통해 외부로 통신합니다.
- EKS: Private Subnet에 Kubernetes 클러스터와 Managed Node Group을 생성합니다. VPC CNI, CoreDNS, kube-proxy, EBS CSI, Pod Identity Agent 애드온을 함께 설치합니다.
- Security: ALB의 HTTP/HTTPS 인바운드와 EKS에서 PostgreSQL(5432), Valkey(6379)로 접근하기 위한 보안 그룹 규칙을 구성합니다.
- RDS: DB Subnet에 암호화된 PostgreSQL Multi-AZ 인스턴스를 생성합니다. Master 비밀번호는 AWS Secrets Manager에서 관리하며 백업, Performance Insights, Enhanced Monitoring을 활성화합니다.
- ElastiCache: Private Subnet에 Serverless Valkey 캐시를 생성합니다. 접속 비밀번호는 무작위로 생성해 Secrets Manager에 저장하고 RBAC 사용자 그룹에 연결합니다.
- State: Terraform State는 S3에 암호화하여 저장하며 S3 Lockfile을 사용해 동시 실행을 방지합니다.

## 주요 기본값

| 항목 | 설정 |
| --- | --- |
| AWS Region | `ap-northeast-2` |
| VPC CIDR | `10.0.0.0/16` |
| EKS Version | `1.36` |
| EKS Node | `t3.medium`, On-Demand, 2대 |
| RDS | PostgreSQL 16.14, `db.t4g.micro`, Multi-AZ |
| ElastiCache | Serverless Valkey, 최대 1GB / 1,000 ECPU/s |

## 사전 준비

- Terraform 1.10 이상
- AWS 리소스를 생성할 수 있는 자격 증명
- State 저장용 S3 Bucket `myproject-terraform-state-47`
- EKS 관리자 권한을 연결할 IAM Role ARN

로컬의 `terraform.tfvars`에 EKS 접근용 Role ARN을 설정합니다. 이 파일은 `.gitignore`에 포함되어 Git에 올라가지 않습니다.

```hcl
code_server_role_arn = "arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>"
```

## 실행 방법

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

생성된 리소스를 제거할 때는 다음 명령을 사용합니다.

```bash
terraform destroy
```

## 주의사항

- `main.tf`의 `public_access_cidrs`는 EKS API 접근을 허용할 공인 IP로 변경해야 합니다.
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

버킷은 `boa-terraform-state-6416` (ap-northeast-2). `use_lockfile = true` 라
락 객체가 `<key>.tflock` 으로 key 마다 따로 생긴다. DynamoDB 테이블은 쓰지 않는다.

### 검증 (backend 접속 없음)

    terraform -chdir=<루트> init -backend=false
    terraform -chdir=<루트> validate
    terraform fmt -recursive -check

### apply

`aws-core` 를 먼저 적용한다. 나머지 셋은 그 뒤 순서 무관하며 동시 작업이 가능하다.
`aws-eks` 는 `terraform.tfvars` 의 `code_server_role_arn` 이 필요하다 (저장소에 없음).

### 삭제 순서

Ingress 가 만든 ALB 는 Terraform state 에 없다. 먼저 치우지 않으면
`aws-core` destroy 가 `DependencyViolation` 으로 막힌다.

    1. kubectl delete ingress ...
    2. ALB · SG · 대상 그룹 소멸 확인
    3. terraform -chdir=aws-eks destroy
    4. terraform -chdir=aws-core destroy

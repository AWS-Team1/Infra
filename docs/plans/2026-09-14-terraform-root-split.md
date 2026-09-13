# Terraform 루트 분리 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Infra` 저장소의 단일 루트 모듈을 컴포넌트별 독립 state 4개 루트(`aws-core` `aws-eks` `aws-rds` `aws-cache`)로 나누고, 모듈을 `aws-modules/`로 재편한다.

**Architecture:** 재사용 모듈은 `aws-modules/`에 backend 없이 두고, 각 루트가 자기 `backend.tf`로 state를 가진다. 루트 간 값 전달은 `terraform_remote_state`로 하며 의존 방향은 `aws-core → {eks, rds, cache}` 1단이다. `modules/security`는 해체해 SG를 보호 대상 모듈로 흡수한다.

**Tech Stack:** Terraform 1.16.2, hashicorp/aws 6.62.0, random 3.9.0, kubernetes 3.2.1, helm 3.3.0. S3 backend + `use_lockfile`.

## 범위

이 계획은 **이미 존재하는 것의 재배치만** 다룬다. 설계 문서의 `aws-ops`(ops ALB)는 신규 구축이라 별도 계획으로 분리한다. 이 계획이 끝나면 루트 4개가 각각 `validate`를 통과하는 상태가 된다.

**apply 하지 않는다.** 모든 검증은 `terraform fmt` + `terraform init -backend=false` + `terraform validate`까지다. `plan`은 `terraform.tfvars`(저장소에 없음)와 backend 접속이 필요하므로 이 계획 밖이다.

## Global Constraints

- 작업 브랜치: `Karfa-choi`에서 `feature/tf-root-split`을 따서 작업. 기준 커밋 `ccbb46e`
- terraform CLI가 PATH에 없다. 모든 터미널 세션에서 먼저 실행:
  `export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"`
- `required_version = ">= 1.10.0"`, `aws = "~> 6.0"`, `random = "~> 3.0"`
- 리전: `ap-northeast-2` (backend 리전도 동일)
- `project_name = "boa"`, `cluster_name = "boa-eks"`
- VPC는 기존 `vpc-07194d5f908bac7cf`를 `data`로 참조한다. 생성하지 않는다
- 서브넷 CIDR — public `192.168.2.0/24` `192.168.3.0/24`, private `192.168.8.0/24` `192.168.9.0/24`, db `192.168.16.0/24` `192.168.17.0/24`
- 가용영역: `ap-northeast-2a`, `ap-northeast-2c`
- state 버킷 `boa-terraform-state-6416`, key는 `aws/<루트>/terraform.tfstate`, `use_lockfile = true`
- `aws-eks` 루트만 `kubernetes`·`helm` provider를 함께 쓴다. 나머지 셋은 `aws`만
- 모든 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

---

## 설계 문서와 다른 점 — 착수 전 확인 필요

설계 문서 §6은 IAM을 `eks-iam-base` / `eks` / `eks-iam-workload` **3모듈**로 나눈다. 근거는 "IAM이 클러스터 ARN을 참조하므로 모듈 하나로는 순환이 생긴다"였다.

**구현해보면 3모듈로도 순환이 남는다.** `aws-modules/eks`의 EBS CSI 애드온이 Pod Identity 연결에 의존하기 때문이다.

```
eks/addons.tf:96  aws_eks_addon.ebs_csi
                    depends_on = [aws_eks_node_group.main,
                                  aws_eks_pod_identity_association.ebs_csi]  ← workload 소관
workload 모듈은 eks 모듈에 의존   →  eks ↔ workload 순환
```

**해법은 클러스터 ARN을 참조 대신 문자열로 조립하는 것이다.**

```hcl
locals {
  cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
}
```

`var.cluster_name`은 루트가 넘기는 리터럴이고 `data` 두 개는 plan 시점에 확정되므로, 클러스터가 없어도 계산된다. IAM 정책의 Resource ARN은 대상이 실재하지 않아도 유효하다.

이렇게 하면 **IAM 전체가 클러스터를 전혀 참조하지 않게 되어 모듈 하나로 충분해진다.** 3모듈을 유지하려면 Karpenter의 역할(base)과 정책(workload)을 갈라야 하는데, 같은 짝을 두 모듈에 나누는 편이 더 나쁘다.

**이 계획은 2모듈(`eks-iam` + `eks`)로 작성했다.** Pod Identity 연결과 access entry는 EKS 리소스이므로 `eks` 모듈에 둔다. 3모듈을 고수하려면 Task 7·8을 다시 써야 하므로 **착수 전에 확정할 것.**

---

## File Structure

**최종 상태**

```
Infra/
├── aws-modules/
│   ├── network/                          기존 modules/network 이동
│   ├── eks-iam/                          신규 — modules/eks/iam.tf 에서 분리
│   ├── eks/                              기존 modules/eks 에서 IAM 제거
│   ├── rds/                              기존 + db SG 흡수
│   ├── elasticache/                      기존 + cache SG 흡수
│   └── aws-load-balancer-controller/     기존 그대로 (내용 변경 없음)
├── aws-core/    backend·versions·providers·main·outputs
├── aws-eks/     동일 + variables(code_server_role_arn) + k8s RBAC 2개
├── aws-rds/     동일
├── aws-cache/   동일
└── docs/
```

**삭제**

```
modules/                 (aws-modules/ 로 이동 후 빈 디렉터리)
modules/security/        해체
backend.tf main.tf provider.tf variables.tf versions.tf    루트에서 제거
boa/k8s/                 gitops 저장소로 이관
```

**모듈 인터페이스**

| 모듈 | 주요 입력 | 주요 출력 |
|---|---|---|
| `network` | `project_name` `cluster_name` `vpc_id` `s3_gateway_endpoint_id` `availability_zones` `*_subnet_cidrs` | `vpc_id` `vpc_cidr` `igw_id` `public_subnet_ids` `private_subnet_ids` `private_subnet_cidrs` `db_subnet_ids` |
| `eks-iam` | `project_name` `cluster_name` `region` | `cluster_role_arn` `node_role_arn` `node_role_name` `karpenter_role_arn` `ebs_csi_role_arn` `bank_of_anthos_role_arn` |
| `eks` | 위 role ARN 5종 + `code_server_role_arn` `private_subnet_ids` `public_access_cidrs` `node_*` | `cluster_name` `cluster_endpoint` `cluster_certificate_authority_data` `cluster_security_group_id` `node_group_name` |
| `rds` | `project_name` `vpc_id` `private_subnet_cidrs` `db_subnet_ids` + 기존 DB 인자 | `db_address` `db_port` `db_name` `master_user_secret_arn` `db_security_group_id` |
| `elasticache` | `project_name` `vpc_id` `private_subnet_cidrs` `subnet_ids` `cache_name` `user_name` `max_*` | `cache_endpoint` `secret_arn` `user_group_id` |

---

## Task 1: 모듈을 aws-modules/ 로 이동

**Files:**
- Move: `modules/*` → `aws-modules/*` (security 제외)
- Modify: `main.tf` (module source 경로 5곳)

**Interfaces:**
- Consumes: 없음 (첫 작업)
- Produces: `aws-modules/{network,eks,rds,elasticache,aws-load-balancer-controller}` 경로. 이후 모든 Task가 이 경로를 쓴다

- [ ] **Step 1: 작업 브랜치 생성**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git switch -c feature/tf-root-split
git log --oneline -1
```

Expected: `ccbb46e docs(infra): ALB 컨트롤러를 Terraform 소유로 유지 (현행)`

- [ ] **Step 2: 이동 전 validate 가 통과하는지 확인 (기준선)**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
terraform -chdir=/c/Claude-workspace/final-project/new-workspace/Infra init -backend=false -input=false >/dev/null && terraform -chdir=/c/Claude-workspace/final-project/new-workspace/Infra validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: git mv 로 이동 (이력 보존)**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
mkdir -p aws-modules
for m in network eks rds elasticache aws-load-balancer-controller; do git mv "modules/$m" "aws-modules/$m"; done
ls aws-modules modules
```

Expected: `aws-modules`에 5개, `modules`에 `security`만 남음

- [ ] **Step 4: validate 가 깨지는지 확인**

```bash
terraform -chdir=/c/Claude-workspace/final-project/new-workspace/Infra validate
```

Expected: FAIL — `Module not found` / `Unreadable module directory` (main.tf가 아직 `./modules/...`를 가리킴)

- [ ] **Step 5: 루트 main.tf 의 source 경로 수정**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
sed -i 's|source = "\./modules/network"|source = "./aws-modules/network"|' main.tf
sed -i 's|source = "\./modules/eks"|source = "./aws-modules/eks"|' main.tf
sed -i 's|source = "\./modules/rds"|source = "./aws-modules/rds"|' main.tf
sed -i 's|source = "\./modules/elasticache"|source = "./aws-modules/elasticache"|' main.tf
sed -i 's|source = "\./modules/aws-load-balancer-controller"|source = "./aws-modules/aws-load-balancer-controller"|' main.tf
grep -n 'source =' main.tf
```

Expected: 6줄 중 5줄이 `./aws-modules/...`, `./modules/security` 1줄만 남음

- [ ] **Step 6: validate 통과 확인**

```bash
terraform -chdir=/c/Claude-workspace/final-project/new-workspace/Infra init -backend=false -input=false >/dev/null && terraform -chdir=/c/Claude-workspace/final-project/new-workspace/Infra validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 7: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "refactor(infra): 모듈을 aws-modules/ 로 이동

security 모듈은 Task 4 에서 해체하므로 이번엔 제외한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: aws-core 루트 생성

**Files:**
- Modify: `aws-modules/network/outputs.tf` (output 1개 추가)
- Create: `aws-core/backend.tf` `aws-core/versions.tf` `aws-core/providers.tf` `aws-core/main.tf` `aws-core/outputs.tf`

**Interfaces:**
- Consumes: Task 1의 `aws-modules/network`
- Produces: `aws-core` 루트의 output — `vpc_id` `vpc_cidr` `public_subnet_ids` `private_subnet_ids` `private_subnet_cidrs` `db_subnet_ids`. Task 5·6·9가 `terraform_remote_state`로 읽는다

- [ ] **Step 1: network 모듈에 private_subnet_cidrs output 추가**

`aws-modules/network/outputs.tf` 끝에 덧붙인다.

```hcl
# rds / elasticache 가 SG 인바운드를 CIDR 로 여는 데 쓴다.
output "private_subnet_cidrs" {
  value = [
    aws_subnet.private_a.cidr_block,
    aws_subnet.private_c.cidr_block
  ]
}
```

- [ ] **Step 2: aws-core/backend.tf 생성**

```hcl
terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "aws/core/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    # S3 네이티브 락 (Terraform 1.10+). DynamoDB 테이블 불필요.
    use_lockfile = true
  }
}
```

- [ ] **Step 3: aws-core/versions.tf 생성**

```hcl
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

- [ ] **Step 4: aws-core/providers.tf 생성**

```hcl
provider "aws" {
  region = "ap-northeast-2"
}
```

- [ ] **Step 5: aws-core/main.tf 생성**

```hcl
# =========================================================
# Network
# - VPC / IGW 는 기존 것을 재사용한다 (생성하지 않음)
#   vpc-07194d5f908bac7cf : 192.168.0.0/16
#   기존 퍼블릭 서브넷 192.168.0.0/24, 192.168.1.0/24 는 건드리지 않는다
# =========================================================

module "network" {
  source = "../aws-modules/network"

  project_name = "boa"
  cluster_name = "boa-eks"

  vpc_id                 = "vpc-07194d5f908bac7cf"
  s3_gateway_endpoint_id = "vpce-0853a7dfbfac3dd62"

  availability_zones = [
    "ap-northeast-2a",
    "ap-northeast-2c"
  ]

  public_subnet_cidrs = [
    "192.168.2.0/24",
    "192.168.3.0/24"
  ]

  private_subnet_cidrs = [
    "192.168.8.0/24",
    "192.168.9.0/24"
  ]

  db_subnet_cidrs = [
    "192.168.16.0/24",
    "192.168.17.0/24"
  ]
}
```

- [ ] **Step 6: aws-core/outputs.tf 생성**

```hcl
# 다른 루트가 terraform_remote_state 로 읽는 계약이다.
# 이름을 바꾸면 소비 루트가 깨진다.

output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "igw_id" {
  value = module.network.igw_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "private_subnet_cidrs" {
  value = module.network.private_subnet_cidrs
}

output "db_subnet_ids" {
  value = module.network.db_subnet_ids
}
```

- [ ] **Step 7: validate**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
terraform -chdir=aws-core init -backend=false -input=false >/dev/null && terraform -chdir=aws-core validate
terraform fmt -recursive -check
```

Expected: `Success! The configuration is valid.` / `fmt`는 출력 없음

- [ ] **Step 8: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "feat(infra): aws-core 루트 추가

network 모듈에 private_subnet_cidrs output 을 더했다.
rds / elasticache 가 SG 인바운드를 CIDR 로 여는 데 쓴다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: db Security Group 을 rds 모듈로 흡수

**Files:**
- Create: `aws-modules/rds/security.tf`
- Modify: `aws-modules/rds/variables.tf` `aws-modules/rds/main.tf:52` `aws-modules/rds/outputs.tf` `main.tf`(루트)

**Interfaces:**
- Consumes: `aws-core`의 `vpc_id` `private_subnet_cidrs`
- Produces: `rds` 모듈이 `var.db_security_group_id`를 더 이상 받지 않는다. 대신 `var.vpc_id` `var.private_subnet_cidrs`를 받고 `db_security_group_id`를 output으로 낸다

- [ ] **Step 1: aws-modules/rds/security.tf 생성**

기존 `modules/security/main.tf:36,130`의 db SG를 옮기되, 인바운드를 EKS 클러스터 SG 참조에서 프라이빗 서브넷 CIDR 허용으로 바꾼다. 이 변경이 `aws-rds` 루트를 `aws-eks`에서 떼어내는 핵심이다.

```hcl
# ===================================================
# DATABASE SECURITY GROUP
# ===================================================
# 인바운드를 EKS 클러스터 SG 참조가 아니라 프라이빗 서브넷 CIDR 로 연다.
# aws-rds 루트가 aws-eks 를 알 필요가 없어진다.
# 느슨해진 경계는 NACL 로 보완한다 (별도 과제).

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for PostgreSQL RDS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_postgresql" {
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = aws_security_group.db.id

  cidr_ipv4   = each.value
  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  description = "Allow PostgreSQL from private subnet ${each.value}"
}
```

- [ ] **Step 2: aws-modules/rds/variables.tf 수정**

`db_security_group_id` 변수를 지우고 두 개를 더한다.

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
perl -0pi -e 's/variable "db_security_group_id" \{\n  type = string\n\}\n\n//' aws-modules/rds/variables.tf
cat >> aws-modules/rds/variables.tf <<'EOF'

variable "vpc_id" {
  description = "db Security Group 을 만들 VPC"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "5432 인바운드를 허용할 프라이빗 서브넷 CIDR"
  type        = list(string)
}
EOF
grep -n "^variable" aws-modules/rds/variables.tf
```

Expected: `db_security_group_id`가 없고 `vpc_id`, `private_subnet_cidrs`가 있음

- [ ] **Step 3: aws-modules/rds/main.tf 의 SG 참조 수정**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
sed -i 's|vpc_security_group_ids = \[var\.db_security_group_id\]|vpc_security_group_ids = [aws_security_group.db.id]|' aws-modules/rds/main.tf
grep -n "vpc_security_group_ids" aws-modules/rds/main.tf
```

Expected: `vpc_security_group_ids = [aws_security_group.db.id]`

- [ ] **Step 4: aws-modules/rds/outputs.tf 에 SG output 추가**

```hcl

output "db_security_group_id" {
  value = aws_security_group.db.id
}
```

- [ ] **Step 5: validate 가 깨지는지 확인**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
terraform -chdir=/c/Claude-workspace/final-project/new-workspace/Infra validate
```

Expected: FAIL — 루트 `main.tf`가 아직 `db_security_group_id`를 넘기고 `vpc_id`·`private_subnet_cidrs`를 안 넘김

- [ ] **Step 6: 루트 main.tf 의 module "rds" 인자 수정**

`db_security_group_id = module.security.db_sg_id` 줄을 지우고 두 줄을 넣는다.

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
sed -i 's|^  db_security_group_id = module\.security\.db_sg_id$|  vpc_id               = module.network.vpc_id\n  private_subnet_cidrs = module.network.private_subnet_cidrs|' main.tf
grep -n -A2 "db_subnet_ids        = module.network.db_subnet_ids" main.tf
```

Expected: `vpc_id`, `private_subnet_cidrs` 두 줄이 보임

- [ ] **Step 7: validate 통과 확인**

```bash
terraform -chdir=/c/Claude-workspace/final-project/new-workspace/Infra validate && terraform -chdir=/c/Claude-workspace/final-project/new-workspace/Infra fmt -recursive -check
```

Expected: `Success! The configuration is valid.` / fmt 출력 없음

- [ ] **Step 8: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "refactor(infra): db Security Group 을 rds 모듈로 흡수

인바운드를 EKS 클러스터 SG 참조에서 프라이빗 서브넷 CIDR 허용으로 바꿨다.
aws-rds 루트가 aws-eks 를 참조하지 않게 하기 위한 변경이다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: cache Security Group 을 elasticache 모듈로 흡수하고 security 모듈 삭제

**Files:**
- Create: `aws-modules/elasticache/security.tf`
- Modify: `aws-modules/elasticache/variables.tf` `aws-modules/elasticache/main.tf:92` `aws-modules/elasticache/outputs.tf` `main.tf`(루트)
- Delete: `modules/security/`

**Interfaces:**
- Consumes: `aws-core`의 `vpc_id` `private_subnet_cidrs`
- Produces: `elasticache` 모듈이 `var.security_group_id`를 받지 않는다. `modules/security`가 사라진다

- [ ] **Step 1: aws-modules/elasticache/security.tf 생성**

```hcl
# =========================================================
# ElastiCache Security Group
# =========================================================
# db SG 와 같은 이유로 CIDR 허용을 쓴다.
# aws-cache 루트가 aws-eks 를 참조하지 않는다.

resource "aws_security_group" "cache" {
  name        = "${var.project_name}-cache-sg"
  description = "Security group for ElastiCache Valkey"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-cache-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cache_valkey" {
  for_each = toset(var.private_subnet_cidrs)

  security_group_id = aws_security_group.cache.id

  cidr_ipv4   = each.value
  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  description = "Allow Valkey from private subnet ${each.value}"
}
```

- [ ] **Step 2: aws-modules/elasticache/variables.tf 수정**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
perl -0pi -e 's/# ElastiCache 전용 Security Group\nvariable "security_group_id" \{\n  type = string\n\}\n\n//' aws-modules/elasticache/variables.tf
cat >> aws-modules/elasticache/variables.tf <<'EOF'

# cache Security Group 을 만들 VPC
variable "vpc_id" {
  type = string
}

# 6379 인바운드를 허용할 프라이빗 서브넷 CIDR
variable "private_subnet_cidrs" {
  type = list(string)
}
EOF
grep -n "^variable" aws-modules/elasticache/variables.tf
```

Expected: `security_group_id`가 없고 `vpc_id`, `private_subnet_cidrs`가 있음

- [ ] **Step 3: aws-modules/elasticache/main.tf 의 SG 참조 수정**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
perl -0pi -e 's/  security_group_ids = \[\n    var\.security_group_id\n  \]/  security_group_ids = [\n    aws_security_group.cache.id\n  ]/' aws-modules/elasticache/main.tf
grep -n -A2 "security_group_ids" aws-modules/elasticache/main.tf
```

Expected: `aws_security_group.cache.id`

- [ ] **Step 4: aws-modules/elasticache/outputs.tf 에 SG output 추가**

```hcl

# 캐시 SG ID
output "cache_security_group_id" {
  value = aws_security_group.cache.id
}
```

- [ ] **Step 5: 루트 main.tf 에서 security 모듈 제거하고 elasticache 인자 수정**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
# security 모듈 호출 블록 삭제
perl -0pi -e 's/module "security" \{.*?\n\}\n\n*//s' main.tf
# elasticache 의 SG 인자 교체
sed -i 's|^  security_group_id = module\.security\.cache_sg_id$|  vpc_id               = module.network.vpc_id\n  private_subnet_cidrs = module.network.private_subnet_cidrs|' main.tf
grep -c 'module.security' main.tf
```

Expected: `0`

- [ ] **Step 6: security 모듈 삭제**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git rm -r modules/security
ls modules 2>/dev/null || echo "modules 디렉터리 없음"
```

Expected: `modules 디렉터리 없음`

- [ ] **Step 7: validate + fmt**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
terraform init -backend=false -input=false >/dev/null && terraform validate && terraform fmt -recursive -check
```

Expected: `Success! The configuration is valid.` / fmt 출력 없음

- [ ] **Step 8: alb-sg 가 완전히 사라졌는지 확인**

```bash
grep -rn "alb_sg\|alb-sg" /c/Claude-workspace/final-project/new-workspace/Infra --include="*.tf" || echo "없음"
```

Expected: `없음` (죽은 코드였으므로 이관 대상이 아니다)

- [ ] **Step 9: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "refactor(infra): security 모듈 해체

cache SG 는 elasticache 모듈로 흡수하고, alb-sg 는 삭제했다.
alb-sg 는 참조하는 곳이 없고 egress 블록이 없어 아웃바운드가 0 인 죽은 코드였다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: aws-rds 루트 생성

**Files:**
- Create: `aws-rds/backend.tf` `aws-rds/versions.tf` `aws-rds/providers.tf` `aws-rds/main.tf` `aws-rds/outputs.tf`

**Interfaces:**
- Consumes: `aws-core` state의 `vpc_id` `private_subnet_cidrs` `db_subnet_ids`
- Produces: `db_address` `db_port` `db_name` `master_user_secret_arn` `db_security_group_id`

- [ ] **Step 1: backend.tf / versions.tf / providers.tf 생성**

`aws-rds/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "aws/rds/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    use_lockfile = true
  }
}
```

`aws-rds/versions.tf`

```hcl
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

`aws-rds/providers.tf`

```hcl
provider "aws" {
  region = "ap-northeast-2"
}
```

- [ ] **Step 2: aws-rds/main.tf 생성**

```hcl
# aws-core 가 만든 네트워크를 읽는다. 이 루트는 aws-eks 를 참조하지 않는다.
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

module "rds" {
  source = "../aws-modules/rds"

  project_name = "boa"

  db_identifier = "boa-postgres"
  db_name       = "boadb"
  db_username   = "boa_admin"

  engine_version = "16.14"
  instance_class = "db.t4g.micro"

  allocated_storage     = 30
  max_allocated_storage = 100

  vpc_id               = data.terraform_remote_state.core.outputs.vpc_id
  private_subnet_cidrs = data.terraform_remote_state.core.outputs.private_subnet_cidrs
  db_subnet_ids        = data.terraform_remote_state.core.outputs.db_subnet_ids

  backup_retention_period                = 7
  monitoring_interval                    = 60
  performance_insights_retention_period  = 7
  enhanced_monitoring_log_retention_days = 7

  # RDSOSMetrics 는 계정·리전 공용 고정 이름. 기존 스택이 이미 보유 중이라 생성하지 않는다.
  create_os_metrics_log_group = false
}
```

- [ ] **Step 3: aws-rds/outputs.tf 생성**

```hcl
output "db_address" {
  value = module.rds.db_address
}

output "db_port" {
  value = module.rds.db_port
}

output "db_name" {
  value = module.rds.db_name
}

output "master_user_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "db_security_group_id" {
  value = module.rds.db_security_group_id
}
```

- [ ] **Step 4: validate**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
terraform -chdir=aws-rds init -backend=false -input=false >/dev/null && terraform -chdir=aws-rds validate && terraform fmt -recursive -check
```

Expected: `Success! The configuration is valid.` / fmt 출력 없음

- [ ] **Step 5: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "feat(infra): aws-rds 루트 추가

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: aws-cache 루트 생성

**Files:**
- Create: `aws-cache/backend.tf` `aws-cache/versions.tf` `aws-cache/providers.tf` `aws-cache/main.tf` `aws-cache/outputs.tf`

**Interfaces:**
- Consumes: `aws-core` state의 `vpc_id` `private_subnet_ids` `private_subnet_cidrs`
- Produces: `cache_endpoint` `secret_arn` `cache_security_group_id`

- [ ] **Step 1: backend.tf / versions.tf / providers.tf 생성**

`aws-cache/backend.tf` — key만 다르다.

```hcl
terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "aws/cache/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    use_lockfile = true
  }
}
```

`aws-cache/versions.tf` — `random`이 필요하다. Valkey 비밀번호를 `random_password`로 만든다.

```hcl
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```

`aws-cache/providers.tf`

```hcl
provider "aws" {
  region = "ap-northeast-2"
}
```

- [ ] **Step 2: aws-cache/main.tf 생성**

```hcl
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =========================================================
# ElastiCache Serverless Valkey
# - 로그인 Session / Cache 용도
# =========================================================

module "elasticache" {
  source = "../aws-modules/elasticache"

  project_name = "boa"

  # Cache / RBAC User 이름
  cache_name = "boa-valkey"
  user_name  = "boa-app"

  vpc_id               = data.terraform_remote_state.core.outputs.vpc_id
  private_subnet_cidrs = data.terraform_remote_state.core.outputs.private_subnet_cidrs

  # EKS Private Subnet A/C 공유
  subnet_ids = data.terraform_remote_state.core.outputs.private_subnet_ids

  # Phase 1 테스트용 낮은 사용량 상한
  max_data_storage    = 1
  max_ecpu_per_second = 1000
}
```

- [ ] **Step 3: aws-cache/outputs.tf 생성**

```hcl
output "cache_endpoint" {
  value = module.elasticache.cache_endpoint
}

output "secret_arn" {
  value = module.elasticache.secret_arn
}

output "user_group_id" {
  value = module.elasticache.user_group_id
}

output "cache_security_group_id" {
  value = module.elasticache.cache_security_group_id
}
```

- [ ] **Step 4: validate**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
terraform -chdir=aws-cache init -backend=false -input=false >/dev/null && terraform -chdir=aws-cache validate && terraform fmt -recursive -check
```

Expected: `Success! The configuration is valid.` / fmt 출력 없음

- [ ] **Step 5: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "feat(infra): aws-cache 루트 추가

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: IAM 을 aws-modules/eks-iam 으로 분리

**Files:**
- Create: `aws-modules/eks-iam/main.tf` `aws-modules/eks-iam/variables.tf` `aws-modules/eks-iam/outputs.tf`
- Modify: `aws-modules/eks/iam.tf` (IAM 역할·정책 제거, Pod Identity 연결만 남김)

**Interfaces:**
- Consumes: 루트가 넘기는 `project_name` `cluster_name` `region`
- Produces: `cluster_role_arn` `node_role_arn` `node_role_name` `karpenter_role_arn` `ebs_csi_role_arn` `bank_of_anthos_role_arn`. Task 8의 `eks` 모듈이 전부 입력으로 받는다

- [ ] **Step 1: eks-iam/variables.tf 생성**

```hcl
variable "project_name" {
  description = "Secrets Manager 경로 접두사"
  type        = string
}

variable "cluster_name" {
  description = "IAM 이름 접두사 및 cluster ARN 조립에 쓴다"
  type        = string
}

variable "region" {
  description = "ARN 조립에 쓴다"
  type        = string
}
```

- [ ] **Step 2: 기존 iam.tf 를 행 범위로 갈라낸다**

`aws-modules/eks/iam.tf`는 481행이고 IAM 과 Pod Identity 가 섞여 있다. 행 범위가 다음과 같이 확인돼 있다 (Task 1~6은 이 파일을 건드리지 않으므로 그대로 유효하다).

| 행 | 내용 | 행선지 |
|---|---|---|
| 1–269 | 헤더 · cluster/node role · 부착 4 · data 2 · karpenter role·policy·부착 | `eks-iam/main.tf` |
| 270–280 | `aws_eks_pod_identity_association.karpenter` | **eks 에 잔류** |
| 281–312 | ebs_csi role · 부착 | `eks-iam/main.tf` |
| 313–324 | `aws_eks_pod_identity_association.ebs_csi` | **eks 에 잔류** |
| 325–423 | node_secrets policy·부착 · bank_of_anthos role·policy·부착 | `eks-iam/main.tf` |
| 424–433 | `aws_eks_pod_identity_association.bank_of_anthos` | **eks 에 잔류** |
| 434–481 | `kubernetes_cluster_role_v1` · `_binding_v1` | eks 에 잔류 → Task 8 에서 루트로 |

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
mkdir -p aws-modules/eks-iam
f=aws-modules/eks/iam.tf
sed -n '1,269p;281,312p;325,423p' $f > aws-modules/eks-iam/main.tf
sed -n '270,280p;313,324p;424,481p' $f > /tmp/eks-iam-keep.tf
mv /tmp/eks-iam-keep.tf $f
```

- [ ] **Step 2b: 갈라진 결과가 맞는지 확인**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
echo "--- eks-iam/main.tf (IAM 만 있어야 함) ---"
grep -c '^resource "aws_iam_' aws-modules/eks-iam/main.tf
grep -c '^resource "aws_eks_pod_identity_association"' aws-modules/eks-iam/main.tf
echo "--- eks/iam.tf (Pod Identity 3 + k8s RBAC 2 만 있어야 함) ---"
grep -c '^resource "aws_eks_pod_identity_association"' aws-modules/eks/iam.tf
grep -c '^resource "aws_iam_' aws-modules/eks/iam.tf
grep -c '^resource "kubernetes_' aws-modules/eks/iam.tf
```

Expected: `13` / `0` / `3` / `0` / `2`

- [ ] **Step 3: 클러스터 ARN 참조를 문자열 조립으로 바꾼다**

`eks-iam/main.tf`의 `data` 블록 아래에 `locals`를 넣고, Karpenter 정책의 `Resource = aws_eks_cluster.main.arn`을 `local.cluster_arn`으로 바꾼다. **이것이 모듈 순환을 없애는 핵심 변경이다.**

```hcl
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# 클러스터 리소스를 참조하지 않고 ARN 을 조립한다.
# var.cluster_name 은 루트가 넘기는 리터럴이고 data 두 개는 plan 시점에 확정되므로
# 클러스터가 없어도 계산된다. IAM 정책의 Resource 는 대상이 실재하지 않아도 유효하다.
locals {
  cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
}
```

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
sed -i 's|        Resource = aws_eks_cluster\.main\.arn|        Resource = local.cluster_arn|' aws-modules/eks-iam/main.tf
grep -n "local.cluster_arn\|aws_eks_cluster.main.arn" aws-modules/eks-iam/main.tf
```

Expected: `local.cluster_arn` 1건, `aws_eks_cluster.main.arn` 0건

- [ ] **Step 4: eks-iam/outputs.tf 생성**

`depends_on`을 output에 붙여, 정책 부착이 끝난 뒤에야 ARN이 소비되게 한다. 이게 없으면 클러스터가 `AmazonEKSClusterPolicy` 부착 전에 생성되어 실패할 수 있다.

```hcl
output "cluster_role_arn" {
  value = aws_iam_role.cluster.arn

  # 정책 부착 전에 클러스터가 만들어지면 실패한다.
  depends_on = [aws_iam_role_policy_attachment.cluster_eks_policy]
}

output "node_role_arn" {
  value = aws_iam_role.node.arn

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_secrets
  ]
}

output "node_role_name" {
  value = aws_iam_role.node.name
}

output "karpenter_role_arn" {
  value      = aws_iam_role.karpenter_controller.arn
  depends_on = [aws_iam_role_policy_attachment.karpenter_controller]
}

output "ebs_csi_role_arn" {
  value      = aws_iam_role.ebs_csi_controller.arn
  depends_on = [aws_iam_role_policy_attachment.ebs_csi_controller]
}

output "bank_of_anthos_role_arn" {
  value      = aws_iam_role.bank_of_anthos.arn
  depends_on = [aws_iam_role_policy_attachment.bank_of_anthos_secrets]
}
```

- [ ] **Step 5: eks 모듈이 역할 ARN 을 변수로 받게 한다**

`aws-modules/eks/variables.tf`에 덧붙인다. 그리고 `region` 변수는 IAM이 빠지면서 쓰이지 않으므로 남겨두되 확인한다.

```hcl

# eks-iam 모듈이 만든 역할 ARN 을 받는다.
variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "karpenter_role_arn" {
  type = string
}

variable "ebs_csi_role_arn" {
  type = string
}

variable "bank_of_anthos_role_arn" {
  type = string
}
```

- [ ] **Step 6: eks 모듈의 리소스 참조를 변수로 바꾼다**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
sed -i 's|role_arn = aws_iam_role\.cluster\.arn|role_arn = var.cluster_role_arn|' aws-modules/eks/main.tf
sed -i 's|node_role_arn   = aws_iam_role\.node\.arn|node_role_arn   = var.node_role_arn|' aws-modules/eks/main.tf
sed -i 's|role_arn        = aws_iam_role\.karpenter_controller\.arn|role_arn        = var.karpenter_role_arn|' aws-modules/eks/iam.tf
sed -i 's|role_arn        = aws_iam_role\.ebs_csi_controller\.arn|role_arn        = var.ebs_csi_role_arn|' aws-modules/eks/iam.tf
sed -i 's|role_arn = aws_iam_role\.bank_of_anthos\.arn|role_arn = var.bank_of_anthos_role_arn|' aws-modules/eks/iam.tf
grep -rn "aws_iam_role\." aws-modules/eks/ || echo "eks 모듈에 IAM 참조 없음"
```

Expected: `eks 모듈에 IAM 참조 없음`

- [ ] **Step 7: eks 모듈의 depends_on 정리**

`aws-modules/eks/main.tf`의 노드그룹에 있던 `depends_on = [aws_iam_role_policy_attachment.node_worker, ...]` 세 줄은 이제 존재하지 않는 리소스를 가리킨다. 제거한다 — 순서는 Step 4의 output `depends_on`이 보장한다.

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
perl -0pi -e 's/  depends_on = \[\n    aws_iam_role_policy_attachment\.node_worker,\n    aws_iam_role_policy_attachment\.node_ecr,\n    aws_iam_role_policy_attachment\.node_cni\n  \]\n\n//' aws-modules/eks/main.tf
perl -0pi -e 's/    aws_iam_role_policy_attachment\.cluster_eks_policy,\n//' aws-modules/eks/main.tf
grep -n "aws_iam_role_policy_attachment" aws-modules/eks/main.tf || echo "제거 완료"
```

Expected: `제거 완료`

- [ ] **Step 8: 두 모듈이 각각 파싱되는지 확인**

모듈 단독으로는 `validate`가 provider 설정을 요구하지 않으므로 디렉터리에서 바로 돌린다.

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
terraform fmt -recursive -check
terraform -chdir=aws-modules/eks-iam init -backend=false -input=false >/dev/null && terraform -chdir=aws-modules/eks-iam validate
```

Expected: fmt 출력 없음 / `Success! The configuration is valid.`

- [ ] **Step 9: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "refactor(infra): IAM 을 aws-modules/eks-iam 으로 분리

클러스터 ARN 을 리소스 참조 대신 문자열로 조립해, IAM 이 클러스터를
전혀 참조하지 않게 했다. 모듈 순환이 사라져 IAM 을 모듈 하나로 묶을 수 있다.
Pod Identity 연결과 access entry 는 EKS 리소스이므로 eks 모듈에 남겼다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8: aws-eks 루트 생성

**Files:**
- Create: `aws-eks/backend.tf` `aws-eks/versions.tf` `aws-eks/providers.tf` `aws-eks/main.tf` `aws-eks/variables.tf` `aws-eks/outputs.tf` `aws-eks/rbac.tf`
- Modify: `aws-modules/eks/iam.tf` (kubernetes RBAC 2개를 루트로 이동)

**Interfaces:**
- Consumes: `aws-core` state의 `private_subnet_ids`. `terraform.tfvars`의 `code_server_role_arn`
- Produces: `cluster_name` `cluster_endpoint` `cluster_certificate_authority_data` `cluster_security_group_id`

- [ ] **Step 1: backend.tf / versions.tf / variables.tf 생성**

`aws-eks/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket  = "boa-terraform-state-6416"
    key     = "aws/eks/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    use_lockfile = true
  }
}
```

`aws-eks/versions.tf` — 이 루트만 provider 셋을 쓴다.

```hcl
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # ALB 컨트롤러(helm)와 secrets-store RBAC 때문에 필요하다.
    # 이 둘을 클러스터 밖으로 빼면 aws 하나로 줄어든다 (개선 과제).
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}
```

`aws-eks/variables.tf`

```hcl
variable "code_server_role_arn" {
  description = "IAM Role ARN used by Code Server for EKS access"
  type        = string
}
```

- [ ] **Step 2: aws-eks/providers.tf 생성**

기존 루트 `provider.tf`와 같되 `module.eks`를 가리킨다.

```hcl
provider "aws" {
  region = "ap-northeast-2"
}

provider "kubernetes" {
  host = module.eks.cluster_endpoint

  cluster_ca_certificate = base64decode(
    module.eks.cluster_certificate_authority_data
  )

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"

    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      "ap-northeast-2"
    ]
  }
}

provider "helm" {
  kubernetes = {
    host = module.eks.cluster_endpoint

    cluster_ca_certificate = base64decode(
      module.eks.cluster_certificate_authority_data
    )

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"

      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        "ap-northeast-2"
      ]
    }
  }
}
```

- [ ] **Step 3: aws-eks/main.tf 생성**

```hcl
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "boa-terraform-state-6416"
    key    = "aws/core/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

module "eks_iam" {
  source = "../aws-modules/eks-iam"

  project_name = "boa"
  cluster_name = "boa-eks"
  region       = "ap-northeast-2"
}

module "eks" {
  source = "../aws-modules/eks"

  project_name       = "boa"
  cluster_name       = "boa-eks"
  kubernetes_version = "1.36"

  private_subnet_ids = data.terraform_remote_state.core.outputs.private_subnet_ids

  public_access_cidrs = [
    "15.165.176.99/32"
  ]

  node_group_name = "boa-eks-node-group"

  node_instance_types = [
    "t3.medium"
  ]
  region = "ap-northeast-2"

  node_capacity_type = "ON_DEMAND"
  node_disk_size     = 30

  node_min_size     = 2
  node_desired_size = 2
  node_max_size     = 2

  node_max_unavailable = 1

  control_plane_log_retention_days = 30

  code_server_role_arn = var.code_server_role_arn

  cluster_role_arn        = module.eks_iam.cluster_role_arn
  node_role_arn           = module.eks_iam.node_role_arn
  karpenter_role_arn      = module.eks_iam.karpenter_role_arn
  ebs_csi_role_arn        = module.eks_iam.ebs_csi_role_arn
  bank_of_anthos_role_arn = module.eks_iam.bank_of_anthos_role_arn
}

# ALB 컨트롤러는 Terraform 소유를 유지한다 (설계 문서 결정 6).
# 분리는 개선 과제다.
module "aws_load_balancer_controller" {
  source = "../aws-modules/aws-load-balancer-controller"

  cluster_name = module.eks.cluster_name
  region       = "ap-northeast-2"
  vpc_id       = data.terraform_remote_state.core.outputs.vpc_id

  depends_on = [
    module.eks
  ]
}
```

- [ ] **Step 4: kubernetes RBAC 2개를 모듈에서 루트로 옮긴다**

`aws-modules/eks/iam.tf`의 `kubernetes_cluster_role_v1.secrets_store_sync`와 `kubernetes_cluster_role_binding_v1.secrets_store_sync`를 잘라내 `aws-eks/rbac.tf`로 옮긴다. 모듈 안에 두면 `aws-modules/eks`가 kubernetes provider를 요구하게 되어 모듈 단독 검증이 어려워진다.

`aws-eks/rbac.tf`

```hcl
# Secrets Store CSI 드라이버가 Secret 을 동기화할 수 있게 하는 RBAC.
# aws-modules/eks 에 두면 그 모듈이 kubernetes provider 를 요구하므로 루트에 둔다.

resource "kubernetes_cluster_role_v1" "secrets_store_sync" {
  metadata {
    name = "secretprovidersyncing-role"
  }

  depends_on = [module.eks]

  rule {
    api_groups = [""]

    resources = [
      "secrets"
    ]

    verbs = [
      "get",
      "create",
      "update",
      "patch",
      "delete",
      "list",
      "watch"
    ]
  }
}

resource "kubernetes_cluster_role_binding_v1" "secrets_store_sync" {
  metadata {
    name = "secretprovidersyncing-rolebinding"
  }

  depends_on = [module.eks]

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.secrets_store_sync.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "secrets-store-csi-driver"
    namespace = "aws-secrets-manager"
  }
}
```

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
grep -c "kubernetes_cluster_role" aws-modules/eks/iam.tf
```

Expected: `0`

- [ ] **Step 5: aws-eks/outputs.tf 생성**

```hcl
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "node_group_name" {
  value = module.eks.node_group_name
}
```

- [ ] **Step 6: validate**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
terraform -chdir=aws-eks init -backend=false -input=false >/dev/null && terraform -chdir=aws-eks validate && terraform fmt -recursive -check
```

Expected: `Success! The configuration is valid.` / fmt 출력 없음

- [ ] **Step 7: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "feat(infra): aws-eks 루트 추가

secrets-store RBAC 2개는 모듈에서 루트로 옮겼다. 모듈 안에 두면
aws-modules/eks 가 kubernetes provider 를 요구해 단독 검증이 어려워진다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 9: 기존 단일 루트 제거

**Files:**
- Delete: `main.tf` `backend.tf` `provider.tf` `variables.tf` `versions.tf` `.terraform.lock.hcl` (루트)
- Delete: `.terraform/` (루트, gitignore 대상이지만 로컬 정리)

**Interfaces:**
- Consumes: Task 2·5·6·8이 만든 루트 4개
- Produces: 저장소에 루트가 4개만 남는다

- [ ] **Step 1: 루트 4개가 모두 validate 를 통과하는지 먼저 확인**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
for r in aws-core aws-eks aws-rds aws-cache; do
  printf "%-10s " "$r"
  terraform -chdir=$r init -backend=false -input=false >/dev/null 2>&1 && terraform -chdir=$r validate >/dev/null 2>&1 && echo OK || echo FAIL
done
```

Expected: 네 줄 모두 `OK`

- [ ] **Step 2: 기존 루트 파일 삭제**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git rm main.tf backend.tf provider.tf variables.tf versions.tf .terraform.lock.hcl
rm -rf .terraform
ls *.tf 2>/dev/null || echo "루트에 .tf 없음"
```

Expected: `루트에 .tf 없음`

- [ ] **Step 3: 남은 디렉터리 확인**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
ls -d */ | sort
```

Expected: `aws-cache/ aws-core/ aws-eks/ aws-modules/ aws-rds/ boa/ docs/`

- [ ] **Step 4: 루트 4개 재검증**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
for r in aws-core aws-eks aws-rds aws-cache; do
  printf "%-10s " "$r"
  terraform -chdir=$r validate >/dev/null 2>&1 && echo OK || echo FAIL
done
terraform fmt -recursive -check
```

Expected: 네 줄 모두 `OK` / fmt 출력 없음

- [ ] **Step 5: 커밋**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "refactor(infra): 기존 단일 루트 제거

루트 4개(aws-core / aws-eks / aws-rds / aws-cache)로 대체했다.
각 루트의 .terraform.lock.hcl 은 첫 init 시 생성된다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 10: lock 파일 커밋과 문서 갱신

**Files:**
- Create: `aws-core/.terraform.lock.hcl` `aws-eks/.terraform.lock.hcl` `aws-rds/.terraform.lock.hcl` `aws-cache/.terraform.lock.hcl`
- Modify: `README.md` `docs/specs/2026-09-14-terraform-root-split-design.md`

**Interfaces:**
- Consumes: Task 9의 최종 구조
- Produces: 다른 사람이 클론해서 바로 `init`할 수 있는 상태

- [ ] **Step 1: lock 파일이 gitignore 대상이 아닌지 확인**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
grep -n "terraform.lock" .gitignore
```

Expected: `!.terraform.lock.hcl` — 명시적으로 추적 대상이다

- [ ] **Step 2: 각 루트에 리눅스·윈도우 해시를 모두 기록**

코드 서버(리눅스)와 로컬(윈도우) 양쪽에서 같은 lock 으로 init 되어야 한다.

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
for r in aws-core aws-eks aws-rds aws-cache; do
  terraform -chdir=$r providers lock -platform=linux_amd64 -platform=windows_amd64
done
ls aws-*/.terraform.lock.hcl
```

Expected: 네 개 파일이 존재

- [ ] **Step 3: README 에 루트 구조와 검증 명령 추가**

`README.md` 끝에 덧붙인다.

```markdown

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
```

- [ ] **Step 4: 설계 문서의 IAM 모듈 구성을 실제와 맞춘다**

`docs/specs/2026-09-14-terraform-root-split-design.md`에서 두 곳을 고친다.

§3 결정 8의 행을 이것으로 바꾼다.

```markdown
| 8 | IAM은 `eks-iam` 1모듈, `aws-eks` 루트 안 | 클러스터 ARN 을 문자열로 조립해 순환을 없앴다. §6 |
```

§6 전체를 이것으로 바꾼다.

```markdown
## 6. IAM 을 별도 모듈로 두는 방법

IAM 이 클러스터 리소스를 참조하면 모듈 간 순환이 생겨 apply 가 거부된다.

    eks-iam ──cluster_role_arn, node_role_arn──→ eks
    eks     ──cluster_arn, cluster_name───────→ eks-iam     ← Cycle

참조를 끊는 방법은 **클러스터 ARN 을 문자열로 조립하는 것**이다.

    locals {
      cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
    }

`var.cluster_name` 은 루트가 넘기는 리터럴이고 `data` 두 개는 plan 시점에 확정되므로
클러스터가 없어도 계산된다. IAM 정책의 Resource 는 대상이 실재하지 않아도 유효하다.

그 결과 IAM 전체가 클러스터를 참조하지 않게 되어 **모듈 하나로 충분하다.**

    eks-iam   IAM 역할·정책·부착 전부 (클러스터 미참조)
         ↓
    eks       클러스터 · 노드그룹 · 애드온 · Pod Identity 연결 · access entry

`aws_eks_pod_identity_association` 과 `aws_eks_access_entry` 는 EKS 리소스이므로
`eks` 모듈에 둔다. 이렇게 해야 `aws_eks_addon.ebs_csi` 의 `depends_on` 이
같은 모듈 안에서 해결된다 — 다른 모듈로 빼면 `eks ↔ iam` 순환이 다시 생긴다.

역할 부착 순서는 output 의 `depends_on` 으로 보장한다.

    output "cluster_role_arn" {
      value      = aws_iam_role.cluster.arn
      depends_on = [aws_iam_role_policy_attachment.cluster_eks_policy]
    }

**IRSA 가 아니라 EKS Pod Identity 를 쓴다.** `aws_iam_openid_connect_provider` 는 없고
신뢰 정책이 `Service = "pods.eks.amazonaws.com"` 이다. 빠진 것이 아니라 선택이다.
```

- [ ] **Step 5: 최종 검증**

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
cd /c/Claude-workspace/final-project/new-workspace/Infra
for r in aws-core aws-eks aws-rds aws-cache; do
  printf "%-10s " "$r"
  terraform -chdir=$r validate >/dev/null 2>&1 && echo OK || echo FAIL
done
terraform fmt -recursive -check
grep -rn "modules/security\|module.security" --include="*.tf" . || echo "security 잔재 없음"
grep -rn '"project-\|/project/' --include="*.tf" . || echo "project 리터럴 없음"
```

Expected: 네 줄 `OK` / fmt 출력 없음 / `security 잔재 없음` / `project 리터럴 없음`

- [ ] **Step 6: 커밋과 푸시**

```bash
cd /c/Claude-workspace/final-project/new-workspace/Infra
git add -A
git commit -m "docs(infra): 루트 구조 README 와 설계 문서 갱신

lock 파일에 linux_amd64 / windows_amd64 해시를 함께 기록해
코드 서버와 로컬 양쪽에서 같은 lock 으로 init 되게 했다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push -u origin feature/tf-root-split
```

---

## 이 계획에 없는 것

| 항목 | 왜 뺐나 |
|---|---|
| `aws-ops` 루트 · ops ALB | 재배치가 아니라 신규 구축이다. 별도 계획 |
| `boa/k8s/` 25개 매니페스트 이관 | gitops 저장소 작업이다. 담당과 일정이 다르다 |
| 루트 `outputs.tf` — gitops 부트스트랩용 output 9종 | ECR·앱 전용 RDS 시크릿 등 없는 리소스를 먼저 만들어야 한다 |
| ALB 컨트롤러 분리 | 설계 문서 §12의 개선 과제 |
| NACL | 설계 문서 §12의 개선 과제 |
| `terraform plan` · `apply` | `terraform.tfvars` 반입과 backend 접속이 필요하다. 코드 서버에서 별도 수행 |
| 코드 서버 IP 하드코딩(`public_access_cidrs`) 변수화 | 설계 문서 §13의 기존 문제. 별도 |

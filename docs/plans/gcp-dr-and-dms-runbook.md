# GCP DR 사이트 + AWS DMS 크로스클라우드 복제 구축 런북

> **대상 독자** — 이 저장소를 처음 보는 팀원, 그리고 발표 시연 담당자.
> **전제** — AWS 쪽(`aws-core` `aws-eks` `aws-rds` `aws-cache` `aws-ops`)은 이미 구축돼 있다.
> **작성** 2026-09-14 / 브랜치 `feature/gcp-and-dms` (기준 `dev`)

---

## 0. 지금 무엇을 만드는가

### 0.1 완성 후 모습

```
                         ┌─────────── Route 53 ───────────┐
                         │  Failover · Health Check       │
                         └───┬────────────────────┬───────┘
                        정상 │                    │ 장애 시
                             ▼                    ▼
╔════════════ AWS (Primary) ═══════════╗  ╔══════ GCP (Standby) ══════╗
║  ap-northeast-2 · 192.168.0.0/16     ║  ║ asia-northeast3 · 10.10/16 ║
║                                      ║  ║                            ║
║  public   2.0/24  3.0/24   ALB       ║  ║  subnet 10.10.0.0/20       ║
║  private  8.0/24  9.0/24   EKS·DMS   ║  ║    pods     10.10.16.0/20  ║
║  db      16.0/24 17.0/24   RDS       ║  ║    services 10.10.32.0/20  ║
║  cache   24.0/24 25.0/24   Redis     ║  ║                            ║
║                                      ║  ║  GKE (Pilot Light 노드 1)  ║
║  ┌────────────┐                      ║  ║  ┌──────────────────────┐  ║
║  │ EKS        │  앱 6종 · ArgoCD     ║  ║  │ GKE  replicas 0      │  ║
║  └─────┬──────┘                      ║  ║  └──────────┬───────────┘  ║
║        │                             ║  ║             │              ║
║  ┌─────▼────────────┐                ║  ║  ┌──────────▼───────────┐  ║
║  │ RDS PostgreSQL16 │                ║  ║  │ Cloud SQL PG16       │  ║
║  │ Multi-AZ         │                ║  ║  │ 사설 IP · ZONAL      │  ║
║  │ accounts·ledger  │                ║  ║  │ accounts·ledger      │  ║
║  └─────┬────────────┘                ║  ║  └──────────▲───────────┘  ║
║        │ 논리 복제 슬롯 ×2           ║  ║             │              ║
║  ┌─────▼────────────┐                ║  ║             │              ║
║  │ DMS 복제 인스턴스 │═══════════════════VPN═══════════╝              ║
║  │ 태스크 ×2        │   4터널 · BGP   ║  ║                            ║
║  └──────────────────┘                ║  ║                            ║
╚══════════════════════════════════════╝  ╚════════════════════════════╝
```

**핵심 — 데이터는 AWS 에서 GCP 로 단방향으로만 흐른다.** GCP 쪽 Cloud SQL 은
복제본이 아니라 처음부터 쓰기 가능한 독립 인스턴스다. 그래서 "승격(promote)"
단계가 없고, 앱이 바라보는 곳을 바꾸는 것이 곧 페일오버다.

### 0.2 Terraform 루트 구성과 의존 방향

```
        ┌──────────┐                    ┌──────────┐
        │ aws-core │                    │ gcp-core │
        └────┬─────┘                    └────┬─────┘
    ┌────┬───┼───┬────┐              ┌───────┼───────┐
    ▼    ▼   ▼   ▼    ▼              ▼               ▼
  eks  rds cache ops  │         gcp-cloudsql      gcp-gke
            ┌─────────┘
            │
            ▼
        ┌───────────┐        ┌──────────┐
        │  aws-dms  │        │ net-link │◄── aws-core + gcp-core
        └───────────┘        └──────────┘        (유일한 양쪽 참조)
```

| 루트 | state key | 하는 일 |
|---|---|---|
| `gcp-core` | `gcp/core` | VPC · 서브넷 · Cloud Router/NAT · **PSA** · 방화벽 |
| `gcp-cloudsql` | `gcp/cloudsql` | Cloud SQL PostgreSQL 16 (사설 IP) + DB 2개 + 계정 |
| `gcp-gke` | `gcp/gke` | GKE 대기 클러스터 + 노드 SA |
| `net-link` | `link/vpn` | AWS ↔ GCP HA VPN (터널 4 · BGP) |
| `aws-dms` | `aws/dms` | 복제 인스턴스 · 엔드포인트 4 · 태스크 2 · 알람 |

**참조 방식이 루트마다 다르다.**

- AWS 루트끼리, GCP 루트끼리는 기존 관례대로 `terraform_remote_state`
- **`aws-dms` 는 GCP 값을 `tfvars` 로 받는다.** GCP 구조가 아직 유동적이라
  `remote_state` 로 묶으면 GCP 리팩터링 때마다 DMS 루트가 깨진다.
  GCP 가 안정되면 `remote_state` 로 승격한다.

### 0.3 왜 GCP DMS 가 아니라 AWS DMS 인가

| | GCP DMS | **AWS DMS (채택)** |
|---|---|---|
| 승격 | 비가역 — 잡이 종료된다 | 승격 개념 자체가 없다 |
| 페일백 | **경로 없음** (대상이 Cloud SQL 뿐) | 가능 — Cloud SQL 을 소스로 지원 |
| 리허설 반복 | 매번 Cloud SQL 재생성 | 태스크 재시작으로 끝 |
| 스키마 이관 | 덤프 기반으로 온전 | **기본 구조만** → 미리 심어야 함 |
| 서비스 요금 | 없음 | 복제 인스턴스 시간당 |

DR 은 왕복이 전제다. 페일백 경로가 도구 안에 있는 쪽을 택했다.

---

## 1. 사전 준비 절차

### 1.1 도구

| 도구 | 확인 | 비고 |
|---|---|---|
| Terraform ≥ 1.10 | `terraform version` | 검증 기준 1.16.2 |
| AWS CLI v2 | `aws sts get-caller-identity` | |
| gcloud CLI | `gcloud version` | |
| psql 16 | `psql --version` | 시퀀스 보정·검증에 쓴다 |

터미널마다 PATH 를 먼저 잡는다.

```bash
export PATH="$PATH:/c/Users/admin/AppData/Local/Microsoft/WinGet/Packages/Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"
```

### 1.2 자격증명

```bash
aws sts get-caller-identity                 # AWS
gcloud auth application-default login       # GCP (Terraform 이 쓰는 자격증명)
gcloud config set project <GCP_PROJECT_ID>
```

### 1.3 GCP 프로젝트 준비 — **API 활성화가 빠지면 apply 가 중간에 죽는다**

```bash
gcloud services enable \
  compute.googleapis.com \
  servicenetworking.googleapis.com \
  sqladmin.googleapis.com \
  container.googleapis.com \
  iam.googleapis.com
```

| API | 없으면 실패하는 지점 |
|---|---|
| `compute` | VPC·서브넷·라우터 생성 |
| `servicenetworking` | **PSA 연결** (Cloud SQL 사설 IP 의 전제) |
| `sqladmin` | Cloud SQL 인스턴스 |
| `container` | GKE |
| `iam` | 노드 서비스 계정 |

계정에 필요한 역할 — `roles/compute.networkAdmin`, `roles/cloudsql.admin`,
`roles/container.admin`, `roles/iam.serviceAccountAdmin`,
`roles/servicenetworking.networksAdmin`, `roles/resourcemanager.projectIamAdmin`.

### 1.4 CIDR 충돌 확인 — **되돌리기 가장 비싼 항목**

| 구간 | 대역 |
|---|---|
| AWS VPC | `192.168.0.0/16` |
| GCP 서브넷 | `10.10.0.0/20` |
| GCP 파드 | `10.10.16.0/20` |
| GCP 서비스 | `10.10.32.0/20` |
| GCP PSA (Cloud SQL) | `/16` 자동 할당 |
| GKE 마스터 | `10.10.255.0/28` |
| VPN 터널 내부 | `169.254.10.0/30` ~ `169.254.10.12/30` |

겹치면 VPN 이 서고 난 뒤에야 드러나고, 그때는 서브넷을 다시 만들어야 한다.
**apply 전에 표를 눈으로 대조할 것.**

### 1.5 tfvars 준비 (저장소에 커밋하지 않는다)

```bash
# gcp-core/terraform.tfvars
gcp_project_id = "<GCP_PROJECT_ID>"

# gcp-cloudsql/terraform.tfvars
gcp_project_id = "<GCP_PROJECT_ID>"
dms_password   = "<강한 비밀번호>"
app_password   = "<AWS 쪽 app-password 와 동일하게>"

# gcp-gke/terraform.tfvars
gcp_project_id = "<GCP_PROJECT_ID>"
master_authorized_cidrs = [
  { cidr_block = "192.168.8.0/24", display_name = "aws-private-a" },
  { cidr_block = "192.168.9.0/24", display_name = "aws-private-c" },
]

# net-link/terraform.tfvars
gcp_project_id = "<GCP_PROJECT_ID>"
tunnel_preshared_keys = {
  "0" = ["<PSK1>", "<PSK2>"]
  "1" = ["<PSK3>", "<PSK4>"]
}

# aws-dms/terraform.tfvars
cloudsql_private_ip   = "<gcp-cloudsql 의 private_ip_address>"
cloudsql_dms_password = "<gcp-cloudsql 의 dms_password 와 동일>"
start_tasks           = false
```

PSK 생성 — 8~64자, `0` 으로 시작 불가.

```bash
openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
```

### 1.6 ⚠️ RDS 재부팅 창 확보

`aws-rds` 에 `rds.logical_replication = 1` 을 추가했다. **정적 파라미터라
재부팅해야 반영되고, Multi-AZ 이므로 재부팅이 AZ 페일오버를 동반할 수 있다.**
서비스 중단이 허용되는 시간대를 미리 잡아둔다.

---

## 2. 구축 과정 (Terraform)

각 단계는 `init → plan → 확인 → apply` 다. 아래는 apply 까지의 요약이다.

### 2-1. AWS RDS 논리 복제 활성화

```bash
cd Infra/aws-rds
terraform init
terraform plan
terraform apply
```

```bash
# 파라미터가 pending-reboot 인지 확인
aws rds describe-db-instances --db-instance-identifier boa-postgres \
  --query 'DBInstances[0].DBParameterGroups[0].ParameterApplyStatus'
```

```bash
# 재부팅 (Multi-AZ 페일오버 동반 가능)
aws rds reboot-db-instance --db-instance-identifier boa-postgres
```

```bash
# 반영 확인 — on 이어야 한다
psql -h <RDS_ENDPOINT> -U boa_admin -d postgres -c "SHOW rds.logical_replication;"
```

### 2-2. GCP 네트워크

```bash
cd Infra/gcp-core
terraform init
terraform plan
terraform apply
```

PSA 연결은 몇 분 걸린다. 완료 확인:

```bash
gcloud services vpc-peerings list --network=boa-vpc
```

### 2-3. Cloud SQL

```bash
cd Infra/gcp-cloudsql
terraform init
terraform plan
terraform apply
terraform output -raw private_ip_address     # aws-dms tfvars 에 넣을 값
```

### 2-4. GKE (DMS 와 무관 — 순서는 자유)

```bash
cd Infra/gcp-gke
terraform init && terraform plan && terraform apply
gcloud container clusters get-credentials boa-gke --region asia-northeast3
```

### 2-5. VPN

```bash
cd Infra/net-link
terraform init
terraform plan
terraform apply
```

**터널이 올라오는 데 수 분 걸린다.** 양쪽에서 확인한다.

```bash
# AWS — 터널 4개가 UP 인지
aws ec2 describe-vpn-connections \
  --query 'VpnConnections[].VgwTelemetry[].{IP:OutsideIpAddress,Status:Status}' --output table
```

```bash
# GCP — BGP 세션이 established 인지
gcloud compute routers get-status boa-router --region asia-northeast3
```

### 2-6. ⛳ 게이트 — 연결 확인 (Terraform 이 보장하지 못한다)

**여기를 통과하지 못하면 DMS 를 만들어도 동작하지 않는다.**

```bash
# AWS private 서브넷의 파드에서 Cloud SQL 사설 IP 로 5432 가 열리는지
kubectl run netcheck --rm -it --image=postgres:16-alpine --restart=Never -- \
  psql "host=<CLOUDSQL_PRIVATE_IP> port=5432 user=dms_writer dbname=accounts sslmode=require" -c "select 1"
```

실패하면 순서대로 본다 — ① VPN 터널 UP ② BGP 경로 전파
③ **GCP PSA 피어링의 `export_custom_routes`** ④ GCP 방화벽 `allow-from-aws`.

### 2-7. GCP 쪽 스키마 선행 이관

AWS DMS 는 **기본 테이블 구조만** 만든다. 인덱스·외래 키·`CREATE RULE`·시퀀스가
빠지므로 대상에 스키마를 먼저 심어야 한다. AWS 쪽에서 쓰는
`gitops/k8s/components/aws/db-bootstrap` 과 같은 Job 을 GCP 용으로 실행한다.

```bash
# 임시로 일회성 실행하는 경우 (GKE 안에서)
kubectl run db-bootstrap-gcp --rm -it --image=postgres:16-alpine --restart=Never -- \
  sh -c 'psql "host=<CLOUDSQL_PRIVATE_IP> user=dms_writer dbname=accounts" -f /sql/0-accounts-schema.sql'
```

```bash
# 확인 — 양쪽 테이블 목록이 같아야 한다
psql -h <CLOUDSQL_PRIVATE_IP> -U dms_writer -d accounts -c '\dt'
psql -h <CLOUDSQL_PRIVATE_IP> -U dms_writer -d ledger   -c '\dt'
```

### 2-8. DMS — 생성만 (태스크는 아직 시작하지 않는다)

```bash
cd Infra/aws-dms
terraform init
terraform plan
terraform apply          # start_tasks = false
```

```bash
# 엔드포인트 연결 테스트 — 4개 모두 successful 이어야 한다
aws dms describe-connections \
  --query 'Connections[].{Endpoint:EndpointIdentifier,Status:Status}' --output table
```

### 2-9. 태스크 시작

`aws-dms/terraform.tfvars` 에서 `start_tasks = true` 로 바꾸고 apply.

```bash
cd Infra/aws-dms
terraform apply
```

```bash
# 전체 적재 진행률
aws dms describe-replication-tasks \
  --query 'ReplicationTasks[].{Task:ReplicationTaskIdentifier,Status:Status,Pct:ReplicationTaskStats.FullLoadProgressPercent}' \
  --output table
```

### 2-10. 복제 검증

```bash
# 소스에 슬롯 2개가 active 인지
psql -h <RDS_ENDPOINT> -U boa_admin -d accounts \
  -c "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained FROM pg_replication_slots;"
```

```bash
# 행 수 비교
psql -h <RDS_ENDPOINT>          -U boa_admin  -d ledger -c "SELECT count(*) FROM transactions;"
psql -h <CLOUDSQL_PRIVATE_IP>   -U dms_writer -d ledger -c "SELECT count(*) FROM transactions;"
```

---

## 3. 콘솔로 하는 경우 (동일 구성)

Terraform 없이 콘솔에서 같은 것을 만들 때의 순서다. 발표 시연이나
수동 복구 상황에서 쓴다.

### 3-1. RDS 논리 복제

1. RDS 콘솔 → **파라미터 그룹** → `boa-postgres16` → 편집
2. `rds.logical_replication` 을 `1` 로 저장
3. RDS → 데이터베이스 → `boa-postgres` → **작업 → 재부팅**
4. 상태가 `사용 가능` 이 되면 파라미터 그룹 상태가 `in-sync` 인지 확인

### 3-2. GCP 네트워크

1. VPC 네트워크 → **VPC 네트워크 만들기** → 이름 `boa-vpc`, 서브넷 생성 모드 **커스텀**
2. 서브넷 추가 — 이름 `boa-subnet`, 리전 `asia-northeast3`, IP 범위 `10.10.0.0/20`
   - **보조 IP 범위** 2개: `boa-pods` `10.10.16.0/20`, `boa-services` `10.10.32.0/20`
   - 비공개 Google 액세스 **사용**
3. VPC 네트워크 → **비공개 서비스 액세스** → 할당 범위 만들기 (`/16`) → 연결 만들기
   - 연결 후 **피어링 편집 → 커스텀 경로 내보내기 사용** ← 빠뜨리면 DMS 가 못 붙는다
4. Cloud Router 만들기 — 이름 `boa-router`, ASN `64514`
5. Cloud NAT 만들기 — 위 라우터에 연결
6. 방화벽 규칙 — `boa-allow-from-aws`, 소스 `192.168.0.0/16`, TCP `5432,443,22`

### 3-3. Cloud SQL

1. SQL → **인스턴스 만들기** → PostgreSQL → 버전 **16**
2. 인스턴스 ID `boa-postgres-dr`, 리전 `asia-northeast3`, 영역 가용성 **단일 영역**
3. **연결** → 비공개 IP **사용**, 네트워크 `boa-vpc` / 공개 IP **사용 안 함**
4. 만들기 후 → **데이터베이스** 탭에서 `accounts`, `ledger` 생성
5. **사용자** 탭에서 `dms_writer`, `boa_app` 생성

### 3-4. VPN (콘솔에서 가장 까다로운 구간)

순서가 고정돼 있다. **GCP 먼저 → AWS → 다시 GCP** 다.

1. **GCP** — 하이브리드 연결 → VPN → **VPN 설정 마법사** → 고가용성 VPN
   - 게이트웨이 이름 `boa-ha-vpn`, 네트워크 `boa-vpc`, 리전 `asia-northeast3`
   - 만들면 **외부 IP 2개**가 할당된다. 적어둔다
2. **AWS** — VPC → 고객 게이트웨이 → **2개 생성** (위 GCP IP 각각, BGP ASN `64514`)
3. **AWS** — VPC → 가상 프라이빗 게이트웨이 생성 (ASN `64512`) → VPC 에 연결
4. **AWS** — Site-to-Site VPN 연결 **2개 생성**
   - 라우팅 옵션 **동적(BGP)**
   - 터널 옵션에서 **내부 IPv4 CIDR 과 사전 공유 키를 직접 지정** (자동 생성하면 GCP 입력이 번거롭다)
   - 생성 후 **터널 외부 IP 4개**와 **내부 주소**를 적어둔다
5. **AWS** — 라우트 테이블 `boa-private-rt-a` / `-c` → **경로 전파**에서 VGW 사용 설정
6. **GCP** — VPN → 피어 VPN 게이트웨이 만들기, 인터페이스 **4개**에 AWS 터널 IP 입력
7. **GCP** — VPN 터널 4개 생성. 각 터널에 AWS 의 사전 공유 키 입력
8. **GCP** — 각 터널에 BGP 세션 구성
   - 라우터 인터페이스 IP = AWS 의 **고객 게이트웨이 내부 주소** + `/30`
   - 피어 IP = AWS 의 **가상 프라이빗 게이트웨이 내부 주소**, 피어 ASN `64512`

터널 상태가 양쪽에서 **UP / established** 인지 확인한 뒤 다음으로 간다.

### 3-5. DMS

1. DMS → **서브넷 그룹** 생성 — private 서브넷 2개(`192.168.8.0/24`, `192.168.9.0/24`)
2. DMS → **복제 인스턴스** 생성
   - 클래스 `dms.t3.medium`, 엔진 `3.5.x`, **퍼블릭 액세스 사용 안 함**
   - 위 서브넷 그룹, SG 는 인바운드 없이 아웃바운드만
3. DMS → **엔드포인트** 4개 생성

   | 유형 | 서버 | DB | 계정 |
   |---|---|---|---|
   | 소스 | RDS 엔드포인트 | `accounts` | `boa_admin` |
   | 소스 | RDS 엔드포인트 | `ledger` | `boa_admin` |
   | 대상 | Cloud SQL 사설 IP | `accounts` | `dms_writer` |
   | 대상 | Cloud SQL 사설 IP | `ledger` | `dms_writer` |

   **대상 엔드포인트 2개에는 반드시 추가 연결 속성을 넣는다.**

   ```
   AfterConnectScript=SET session_replication_role = replica
   ```

   없으면 전체 적재가 외래 키 위반으로 실패한다.

4. 각 엔드포인트에서 **연결 테스트** → 4개 모두 성공 확인
5. DMS → **데이터베이스 마이그레이션 태스크** 2개 생성
   - 마이그레이션 유형 **기존 데이터 마이그레이션 및 지속적인 변경 복제**
   - 대상 테이블 준비 모드 **아무 작업도 수행 안 함** ← 스키마를 미리 심었으므로
   - 테이블 매핑 — 스키마 `public`, 테이블 `%` 포함
6. 태스크 시작 → 전체 적재 100% → 상태 **진행 중인 복제** 확인

### 3-6. CloudWatch 알람 2개

| 알람 | 지표 | 조건 |
|---|---|---|
| 복제 지연 | `AWS/DMS` → `CDCLatencyTarget` | 3분 초과 3회 연속 |
| **소스 스토리지** | `AWS/RDS` → `FreeStorageSpace` | 5GB 미만 |

두 번째가 특히 중요하다. 복제가 멈추면 슬롯이 WAL 을 붙들어 **소스 RDS
디스크가 찬다.** DR 하려고 붙인 복제가 주 사이트를 죽이는 사고다.

---

## 4. 페일오버 절차

`setval` 을 빠뜨리면 전환 직후 첫 송금이 PK 충돌로 죽는다. **필수 단계다.**

```bash
# 1. 복제 지연이 0 에 수렴했는지 (여기까지가 실측 RPO)
aws dms describe-replication-tasks \
  --query 'ReplicationTasks[].{Task:ReplicationTaskIdentifier,Status:Status}' --output table
```

```bash
# 2. 태스크 중지
aws dms stop-replication-task --replication-task-arn <TASK_ARN>
```

```bash
# 3. 시퀀스 보정 — AWS DMS 는 시퀀스를 복제하지 않는다
psql -h <CLOUDSQL_PRIVATE_IP> -U dms_writer -d ledger \
  -c "SELECT setval(pg_get_serial_sequence('transactions','transaction_id'), (SELECT COALESCE(MAX(transaction_id),1) FROM transactions));"
```

```bash
# 4. 앱을 Cloud SQL 로 전환 (GitOps — replicas 를 올리고 DB 주소를 바꾼다)
```

```bash
# 5. 복제 슬롯 정리 — AWS 가 살아 있다면 반드시 지운다
psql -h <RDS_ENDPOINT> -U boa_admin -d accounts -c "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE NOT active;"
```

---

## 5. 미정 사항과 결정 시한

| 항목 | 내용 | 시한 |
|---|---|---|
| **PG 16 Multi-AZ 페일오버 시 슬롯 생존** | 슬롯 동기화(`sync_replication_slots`)는 PG **17** 기능이다. 16.14 에는 없다. 페일오버 후 슬롯이 사라지면 전체 적재부터 다시 해야 한다. **강제 페일오버로 실측 필요** | DMS 가동 직후 |
| GCP 리전 확정 | `asia-northeast3`(서울) 기본값. 비용·지연 비교 필요 | gcp-core apply 전 |
| Cloud SQL 티어 | `db-custom-1-3840` 로 잡음. 전체 적재 속도가 부족하면 상향 | 전체 적재 시점 |
| 대기 DB 쓰기 보호 | Cloud SQL 이 상시 쓰기 가능하다. `ALTER ROLE boa_app SET default_transaction_read_only = on` 가드레일을 걸지 여부 | 페일오버 리허설 전 |
| SNS 알람 수신자 | `alarm_sns_topic_arns` 가 비어 있어 지금은 상태만 바뀐다 | 시연 전 |
| GCP db-bootstrap 컴포넌트 | 지금은 일회성 명령. `gitops/k8s/components/gcp/db-bootstrap` 로 정식화 필요 | GKE 배포 시 |

---

## 6. 알아둘 함정 5가지

1. **PSA 피어링의 커스텀 경로 내보내기** — GCP VPC 피어링은 전이되지 않는다.
   이걸 켜지 않으면 Cloud SQL 이 VPN 너머 AWS 대역으로 가는 경로를 모른다.
2. **외래 키 → 전체 적재 실패** — DMS 는 테이블 순서를 보장하지 않는다.
   대상 엔드포인트에 `AfterConnectScript=SET session_replication_role = replica` 필수.
3. **시퀀스는 복제되지 않는다** — AWS 문서에 명시된 제한이다. 페일오버 시 `setval`.
4. **멈춘 태스크가 소스를 죽인다** — 슬롯이 WAL 을 붙든다. `FreeStorageSpace` 알람 필수.
5. **`terraform apply` 가 복제를 멈출 수 있다** — 태스크 인자를 바꾸면 실행 중인
   태스크가 중지된다. apply 후 상태를 반드시 확인한다.

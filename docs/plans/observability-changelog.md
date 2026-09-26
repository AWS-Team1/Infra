# 관측 스택 변경 내역 — Infra

- 최초 구현 브랜치: `feat/observability-stack`
- 최종 lifecycle 통합 브랜치: `feature/final-infra-integration`
- 작성: 2026-09-26
- 담당: 보안·관측 파트
- 짝 문서: `gitops/docs/observability-changelog.md`

검증 상태 — `terraform fmt -recursive -check` 통과, `terraform validate` 통과
(`aws-observability`, `aws-rds` 두 루트 모두). `terraform plan` 은 원격 상태가
필요해 실행하지 않았다.

---

## 1. 요약

최종 통합에서는 observability AWS 리소스를 독립 root로 유지하되 장기 보존 대상인
telemetry archive와 두 Secret container의 소유권을 `persistent` root로 옮겼다.
routine destroy는 관측 실행 리소스만 제거하고 보존 데이터는 남긴다.

---

## 2. 신규 — `aws-observability/` (루트 모듈)

기존 루트들과 같은 구성을 따랐다. `environment.tf`로 `../env` 계약을 사용하고 1단 평면 구조를 유지해서
`aws-rds` · `aws-cache` · `aws-dms` 를 참조하지 않는다.

| 파일 | 내용 |
|---|---|
| `backend.tf` | 상태 키 `aws/observability/terraform.tfstate`. 버킷·락 방식은 기존과 동일 |
| `providers.tf` | `default_tags` 의 `Component = "observability"` |
| `versions.tf` | aws `~> 6.0` 만. kubernetes·helm 공급자를 쓰지 않는다 |
| `environment.tf` | 공통 project/region/state/public DNS/Grafana host 계약 |
| `variables.tf` | `enable_telemetry_archive` · `enable_log_data_protection` |
| `main.tf` | 모듈 호출 + Route53 A 레코드 |
| `outputs.tf` | gitops 에 넣어야 하는 값 4개 + 확인용 + `secret_fill_commands` |

### 읽는 원격 상태 3개

```
aws/core/terraform.tfstate  → vpc_id · private_subnet_cidrs
aws/eks/terraform.tfstate   → cluster_name
aws/ops/terraform.tfstate   → ops_alb_https_listener_arn · ops_alb_security_group_id · alb_dns_name · alb_zone_id
```

**적용 순서** — `aws-core` → `aws-eks` → `aws-ops` → `aws-observability`.
앞의 셋이 없으면 원격 상태 읽기에서 멈춘다.

### Secrets Manager 껍데기 2개

`persistent` root가 `/boa/observability/whatap` · `/boa/observability/grafana` 를 만들지만
**값은 넣지 않는다.** 라이선스 키가 tfvars·state·CI 로그에 남지 않게 하려는 것이다.
채우는 명령은 `terraform output secret_fill_commands` 가 그대로 출력한다.

routine destroy에는 포함되지 않고 `full_teardown=true`에서만 제거된다.
`recovery_window_in_days = 0`이라 clean apply에서 같은 이름을 다시 사용할 수 있다.

---

## 3. 신규 — `aws-modules/observability/`

### 3.1 CloudWatch 로그 그룹 3개 (`main.tf`)

| 이름 | 용도 | 보존 |
|---|---|---|
| `/aws/eks/boa-eks/application` | 수집기 `awscloudwatchlogs` exporter 수신구 | 30일 |
| `/aws/eks/boa-eks/otel-emf` | 수집기 `awsemf` exporter 수신구 (지표) | 30일 |
| `/aws/logs-data-protection/boa-eks` | 마스킹 감지 기록 (감사 증적) | 90일 |

EKS 컨트롤 플레인 로그 그룹(`/aws/eks/boa-eks/cluster`)과 별개다. 그쪽은
`aws-modules/eks/main.tf` 가 소유하고 AWS 가 직접 쓴다 — 건드리지 않았다.

### 3.2 데이터 보호 정책 — 민감정보 마스킹

`aws_cloudwatch_log_data_protection_policy` 를 앱 로그와 EMF 로그 두 그룹에 건다.

커스텀 식별자 3개 (`variables.tf` 의 `custom_data_identifiers`):

| 이름 | 정규식 | 대상 |
|---|---|---|
| BoaAccountId | `[0-9]{10}` | 10자리 계좌번호 후보 |
| BoaRoutingNumber | `[0-9]{9}` | `LOCAL_ROUTING_NUM` 후보 |
| BoaJwtToken | `eyJ...\.…\.…` | userservice 가 발급하는 RS256 JWT |

관리형 식별자 2개 — `EmailAddress` · `CreditCardNumber`.

**정책 문서의 Statement 순서가 의미를 갖는다.** `Audit` 가 먼저 와야 무엇이
걸렸는지 기록되고, 그 다음 `Deidentify` 가 마스킹한다.

> ⚠️ 데이터 보호 정책은 수집 시점에 민감 데이터를 탐지해 기본 조회에서 마스킹한다.
> 저장된 원본은 유지되며 `logs:Unmask` 권한이 있는 주체만 볼 수 있다.

### 3.3 텔레메트리 장기 보관 S3

`persistent` root가 버킷 `boa-telemetry-archive-<계정ID>`를 소유한다. 와탭 보존
기간·체험 만료와 무관한 우리 쪽 원본을 routine destroy 이후에도 남긴다.

- 퍼블릭 접근 4종 차단, AES256 암호화
- 라이프사이클 — 30일 STANDARD_IA, 365일 만료, 중단된 멀티파트 7일 정리
- 버킷 정책 — `aws:SecureTransport = false` 이면 전부 Deny
- 버전 관리는 `Suspended`. 감사 대상이 되면 `Enabled` 로 바꾼다

명시적 `full_teardown=true`에서는 `force_destroy`로 객체와 version까지 영구 삭제한다.
따라서 archive 보존 여부를 확인하지 않고 full teardown을 실행하면 안 된다.

> ⚠️ **이 버킷에는 CloudWatch 데이터 보호 정책이 걸리지 않는다.** 그 기능은
> CloudWatch Logs 전용이다. 그래서 마스킹을 수집기의 `redaction`·`transform`
> 프로세서에서 한 번 더 한다 — 그것이 세 목적지(와탭·CloudWatch·S3) 모두에
> 걸리는 유일한 지점이다. gitops 쪽 변경 내역의 4항 참조.

### 3.4 IAM — Pod Identity 역할 2개 (`iam.tf`)

이 클러스터는 IRSA(OIDC)를 쓰지 않는다. `eks-iam` 모듈의 karpenter·ebs-csi
역할과 같이 신뢰 주체를 `pods.eks.amazonaws.com` 으로 두었다.

**`boa-eks-otel-collector-role`**

| 허용 | 범위 |
|---|---|
| logs:CreateLogStream · PutLogEvents · DescribeLogStreams · PutRetentionPolicy | 위 로그 그룹 2개만 |
| logs:DescribeLogGroups | `*` (리소스 제한 미지원) |
| cloudwatch:PutMetricData | 네임스페이스 `BoA/Observability` · `ContainerInsights` 조건 |
| eks:DescribeCluster | 자기 클러스터 ARN |
| ec2:DescribeTags | `*` (resourcedetection) |
| secretsmanager:GetSecretValue | `/boa/observability*` 만 |
| s3:PutObject · AbortMultipartUpload | 텔레메트리 버킷만 |

**`CreateLogGroup` 을 주지 않았다** — 로그 그룹은 Terraform 이 미리 만들고,
수집기가 임의 경로를 만들지 못하게 한다. 이름이 틀리면 조용히 실패하지 않고
`AccessDenied` 로 드러난다.

**`logs:Unmask` 를 명시적으로 Deny 했다.** 정책이 여럿 붙어도 Deny 가 이긴다.

**`boa-eks-grafana-role`** — CloudWatch 지표·로그 읽기 전용.
`logs:Unmask` 역시 Deny 다. Grafana 화면에서도 계좌번호는 가려진 채 보여야 한다.

### 3.5 `boa-eks-cloudwatch-logs-unmask` — 만들지만 부착하지 않는다

감사 시 사람이 의도적으로 자기 역할에 붙인다. 부착 자체가 CloudTrail 에 남으므로
"누가 언제 마스킹을 걷었는가"가 추적된다. 태그에 `AttachedTo = "none-by-design"`
을 달아 두었다.

확인 — 출력이 비어야 정상:

```bash
aws iam list-entities-for-policy --policy-arn $(terraform output -raw logs_unmask_policy_arn) --query '{roles:PolicyRoles,users:PolicyUsers,groups:PolicyGroups}'
```

### 3.6 Grafana 를 ops ALB 에 붙인다 (`alb.tf`)

`aws-modules/ops-alb` 가 이미 자리를 비워 두었다 — `https_listener_arn` 출력과
"우선순위 대역 — argocd 100번대, 관측성은 200번대로 둔다" 주석.

- 대상 그룹 `boa-grafana-tg` (ip, 3000, 헬스체크 `/api/health`)
- 리스너 규칙 우선순위 200, host-header `grafana.bespinglobal.site`
- ops ALB SG에서 private subnet CIDR의 Grafana port 3000으로만 egress 추가
- **리스너 자체는 건드리지 않는다.** 규칙만 이 모듈이 소유하므로 `aws-ops` 상태와 충돌하지 않는다

대상 등록은 Terraform 이 하지 않는다. gitops 의 `TargetGroupBinding` 이 파드 IP 를
넣는다 — 생성 직후 대상 0개가 정상이다.

---

## 4. 수정 — `aws-modules/rds/`

**DB 담당 겸임 범위의 변경이다. 기본값은 대부분 현재 동작을 유지한다.**

### 4.1 변수 6개 추가 (`variables.tf`, +46줄)

| 변수 | 기본값 | 현재 동작 대비 |
|---|---|---|
| `log_min_duration_statement_ms` | 1000 | 동일 (리터럴 `"1000"` 을 변수화만) |
| `enable_pgaudit` | false | 동일 — plan 에 아무것도 안 나온다 |
| `pgaudit_log_classes` | `ddl,role` | `enable_pgaudit` 가 false 면 미사용 |
| `log_parameter_max_length` | **0** | **변경됨** ↓ |
| `log_statement` | none | 동일 (PostgreSQL 기본값) |

### 4.2 파라미터 그룹 변경 (`main.tf`, +58/−1)

**실제 동작이 바뀌는 것 3개:**

| 파라미터 | 값 | 영향 |
|---|---|---|
| `log_parameter_max_length` | 0 | **보안 강화.** 쿼리 로그에 바인딩 파라미터를 남기지 않는다 — 계좌번호가 SQL 로그로 새는 경로를 막는다 |
| `log_connections` | 1 | 접속 기록. 로그량 소폭 증가 |
| `log_disconnections` | 1 | 연결 종료 기록. 로그량 소폭 증가 |

`log_parameter_max_length` 를 0 으로 둔 것이 유일한 "기본값으로 동작을 바꾼"
항목이다. PostgreSQL 기본값은 `-1`(파라미터 전문 기록)이고, 보안 담당 관점에서는
0 이 맞는 기본값이라 판단했다. **되돌리려면 `log_parameter_max_length = -1`.**

**조건부로 둔 것 2개** — `enable_pgaudit = true` 일 때만 파라미터가 추가된다.

`dynamic "parameter"` 로 감싼 이유: `shared_preload_libraries` 는 정적
파라미터다. 기본값과 같은 값을 명시적으로 쓰기만 해도 파라미터 그룹이
`pending-reboot` 로 표시될 수 있고, **Multi-AZ 에서 그 재부팅은 AZ 페일오버를
동반한다.** 껐을 때 plan 에 아무것도 나타나지 않아야 "안 건드렸다"가 성립한다.

pgaudit 를 켤 때 순서 — ① `enable_pgaudit = true` apply → ② 인스턴스 재부팅 →
③ `psql` 에서 `CREATE EXTENSION pgaudit;`. **③을 빼면 로그가 나오지 않는다.**

### 4.3 `aws-rds/main.tf` 는 건드리지 않았다

루트가 새 변수를 넘기지 않으므로 전부 기본값이 적용된다.

---

## 5. 배포 절차

```bash
cd Infra/persistent
terraform init
terraform plan
terraform apply

cd Infra/aws-observability
terraform init
terraform plan -out=obs.tfplan
terraform apply obs.tfplan

# 시크릿 값 채우기 — 명령이 출력으로 나온다
terraform output -raw secret_fill_commands

# gitops 에 넣을 값 4개
terraform output application_log_group_name
terraform output emf_log_group_name
terraform output telemetry_bucket_name
terraform output -raw grafana_target_group_arn

# ALB SG (gitops 의 TargetGroupBinding 에 필요)
terraform -chdir=../aws-ops output -raw ops_alb_security_group_id
```

GitOps의 Grafana workload/TargetGroupBinding은 Terraform `aws-eks-platform`이 LBC를
준비한 이후 별도 수동 절차로 배포한다.

RDS 변경은 별도다. 보안 강화만 적용하려면:

```bash
cd Infra/aws-rds
terraform plan     # log_parameter_max_length · log_connections · log_disconnections 3건만 보여야 한다
terraform apply
```

---

## 6. 미결 항목

결정 시한 — **발표 1주 전**.

| # | 미결 | 확인 방법 | 영향 |
|---|---|---|---|
| 1 | 자리수 기반 마스킹 규칙의 오탐률 | `/aws/logs-data-protection/boa-eks` 에 며칠 쌓아 보고 걸린 건수·문맥을 센다 | epoch 초(10자리)·pod uid 조각이 계좌번호로 잡힌다. 접두사·키 이름을 포함한 규칙으로 좁혀야 한다 |
| 2 | 관리형 데이터 식별자 ARN 두 개가 실제로 유효한가 | `terraform plan` 에서 검증되지 않는다. apply 후 `aws logs get-data-protection-policy` | 잘못된 ARN 이면 apply 시점에 실패한다 |
| 3 | `awsemf` 의 사용자 지정 지표 개수와 요금 | apply 후 `aws cloudwatch list-metrics --namespace BoA/Observability \| jq '.Metrics \| length'` | 요금이 지표 개수당이다. `metric_declarations` 로 좁혀 두었으나 실측 필요 |
| 4 | 텔레메트리 S3 의 일일 증가량 | 1주 후 `aws s3 ls --summarize --recursive` | 365일 보존이 과한지 판단 |
| 5 | `/boa/observability*` 범위가 앱 시크릿과 겹치지 않는가 | `aws secretsmanager list-secrets --query 'SecretList[].Name'` | 겹치면 수집기가 앱 시크릿을 읽을 수 있다 |
| 6 | 관측용 AppProject 분리 | gitops 변경 내역 6항 참조 | 현재 `boa` 프로젝트 권한을 넓혔다 — 앱 Application 도 ClusterRole 을 만들 수 있게 됐다 |
| 7 | RDS 로그 그룹(`/aws/rds/instance/boa-postgres/postgresql`)에도 데이터 보호 정책이 필요한가 | `log_parameter_max_length > 0` 으로 바꿀 때 필수 | 0 인 지금은 파라미터가 안 찍히므로 불필요 |

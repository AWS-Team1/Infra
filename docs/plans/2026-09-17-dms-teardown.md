# DMS · Cloud SQL · RDS 철거 절차

> 2026-09-16 구축분 기준. 계정 `769413326616` / `ap-northeast-2`
> 만든 순서의 **역순**이다. 어기면 "삭제할 수 없음"으로 막히거나 고아 자원이 남는다.

## 전체 순서

```
① 태스크 정지 → ② 태스크 삭제 → ③ 소스 슬롯 정리
→ ④ 엔드포인트 4개 → ⑤ 복제 인스턴스 → ⑥ 서브넷 그룹
→ ⑦ 시크릿 · IAM 정책 · 평가 버킷
→ ⑧ Cloud SQL (보호 해제 후)
→ ⑨ aws-cd-bootstrap → aws-rds
→ ⑩ 배스천 · SG 규칙 · 경로 전파
```

## 대상 자원

| 자원 | 식별자 |
|---|---|
| 태스크 | `boa-task-accountsdb` / `boa-task-ledger` |
| 복제 인스턴스 | `boa-dms-instance` |
| 서브넷 그룹 | `boa-dms-subnet-group` |
| 엔드포인트 | `boa-src-accountsdb` `boa-src-ledger` `boa-tgt-accountsdb` `boa-tgt-ledger` |
| 시크릿 | `/boa/dms/rds-source` |
| IAM 역할 | `DMSSecretManagerAccessRole-boadmsrds-source` |
| 평가 버킷 | `dms-assessment-run-2026-09-16-21-10-52` |
| RDS | `boa-postgres` (Terraform `aws-rds`) |
| Cloud SQL | `boa-postgres-dr` (Terraform `gcp-cloudsql`) |

---

## ① 태스크 정지

```bash
aws dms stop-replication-task --region ap-northeast-2 --replication-task-arn arn:aws:dms:ap-northeast-2:769413326616:task:M2U3Q62W3ZF6DCM6IWZQKO325M
```

```bash
aws dms stop-replication-task --region ap-northeast-2 --replication-task-arn arn:aws:dms:ap-northeast-2:769413326616:task:6QGQJDKUHVDAJJCAC2AGBY5DBE
```

`stopped` 가 될 때까지 기다린다. `running` 인 채로는 삭제되지 않는다.

```bash
aws dms describe-replication-tasks --region ap-northeast-2 --query "ReplicationTasks[].{Id:ReplicationTaskIdentifier,Status:Status}" --output table
```

## ② 태스크 삭제

```bash
aws dms delete-replication-task --region ap-northeast-2 --replication-task-arn arn:aws:dms:ap-northeast-2:769413326616:task:M2U3Q62W3ZF6DCM6IWZQKO325M
```

```bash
aws dms delete-replication-task --region ap-northeast-2 --replication-task-arn arn:aws:dms:ap-northeast-2:769413326616:task:6QGQJDKUHVDAJJCAC2AGBY5DBE
```

## ③ 소스의 복제 슬롯 정리 ⚠️ 놓치기 쉬움

**태스크를 지워도 RDS의 복제 슬롯은 남는다.** 남은 슬롯은 WAL을 계속 붙들어 스토리지를 먹는다.
곧 RDS를 지울 거라 무해해 보이지만, destroy 가 실패하거나 미뤄지면 그대로 쌓인다.

DBeaver에서 AWS `accountsdb` · `ledgerdb` **양쪽** 실행:

```sql
SELECT slot_name, active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots;
```

```sql
SELECT pg_drop_replication_slot('<slot_name>');
```

## ④ 엔드포인트 4개

```bash
for a in $(aws dms describe-endpoints --region ap-northeast-2 --query "Endpoints[].EndpointArn" --output text); do aws dms delete-endpoint --region ap-northeast-2 --endpoint-arn $a; done
```

cmd.exe 면 하나씩:

```bash
aws dms describe-endpoints --region ap-northeast-2 --query "Endpoints[].{Id:EndpointIdentifier,Arn:EndpointArn}" --output table
```

```bash
aws dms delete-endpoint --region ap-northeast-2 --endpoint-arn <ENDPOINT_ARN>
```

## ⑤ 복제 인스턴스 → ⑥ 서브넷 그룹

```bash
aws dms delete-replication-instance --region ap-northeast-2 --replication-instance-arn arn:aws:dms:ap-northeast-2:769413326616:rep:LQASOM7YLFCMNIL4QWTRZN673Q
```

```bash
aws dms wait replication-instance-deleted --region ap-northeast-2 --replication-instance-arn arn:aws:dms:ap-northeast-2:769413326616:rep:LQASOM7YLFCMNIL4QWTRZN673Q
```

**인스턴스가 완전히 사라진 뒤에야** 서브넷 그룹이 지워진다. `wait` 를 빼면 다음 줄이 실패한다.

```bash
aws dms delete-replication-subnet-group --region ap-northeast-2 --replication-subnet-group-identifier boa-dms-subnet-group
```

## ⑦ DMS 부속 자원

```bash
aws secretsmanager delete-secret --region ap-northeast-2 --secret-id /boa/dms/rds-source --force-delete-without-recovery
```

```bash
aws iam delete-role-policy --role-name DMSSecretManagerAccessRole-boadmsrds-source --policy-name AllowBoaDmsSourceSecret
```

```bash
aws s3 rm s3://dms-assessment-run-2026-09-16-21-10-52 --recursive
```

```bash
aws s3 rb s3://dms-assessment-run-2026-09-16-21-10-52
```

> **`dms-vpc-role` 과 `dms-cloudwatch-logs-role` 은 지우지 않는다.**
> 이름이 고정된 계정·리전 공용 역할이라 다음 구축에서 그대로 쓴다.

콘솔이 만든 `DMSSecretManagerAccessRole-...` 역할 자체를 지우려면 인라인·연결 정책을 먼저 뗀다.

```bash
aws iam list-attached-role-policies --role-name DMSSecretManagerAccessRole-boadmsrds-source
```

---

## ⑧ Cloud SQL — 보호 해제가 먼저다

`gcp-cloudsql/main.tf` 의 `deletion_protection = true` 때문에 바로 destroy 하면 거부된다.

`false` 로 바꾼 뒤:

```bash
terraform -chdir=gcp-cloudsql apply
```

```bash
terraform -chdir=gcp-cloudsql destroy
```

> `google_sql_database` 가 `deletion_policy = "ABANDON"` 이라 Terraform 이 DB 자체를 지우려 하지는 않지만,
> **인스턴스가 사라지면 안의 DB도 함께 사라진다.** state 에서만 빠지는 것이 아니다.

## ⑨ RDS — 참조하는 루트를 먼저 걷는다

**`aws-cd-bootstrap` 이 `aws-rds` 의 출력을 읽는다.**

```
aws-cd-bootstrap/main.tf:93    rds.outputs.master_user_secret_arn
aws-cd-bootstrap/main.tf:121   rds.outputs.db_address   (db.boa.internal CNAME)
```

RDS 를 먼저 destroy 하면 그 루트의 plan 이 깨진다.

```bash
terraform -chdir=aws-cd-bootstrap destroy
```

```bash
terraform -chdir=aws-rds destroy
```

> ⚠️ **`skip_final_snapshot = true` 다** (`aws-modules/rds/main.tf:85`).
> 최종 스냅샷이 남지 않아 되돌릴 방법이 없다.

보존이 필요하면 destroy 전에:

```bash
aws rds create-db-snapshot --region ap-northeast-2 --db-instance-identifier boa-postgres --db-snapshot-identifier boa-postgres-manual-20260917
```

```bash
aws rds wait db-snapshot-available --region ap-northeast-2 --db-snapshot-identifier boa-postgres-manual-20260917
```

---

## ⑩ 배스천과 임시 변경 되돌리기

```bash
aws ec2 terminate-instances --region ap-northeast-2 --instance-ids <INSTANCE_ID>
```

```bash
aws ec2 revoke-security-group-ingress --region ap-northeast-2 --group-id sg-0215fd533afbc2534 --protocol tcp --port 5432 --source-group <BASTION_SG>
```

```bash
aws ec2 disable-vgw-route-propagation --region ap-northeast-2 --route-table-id rtb-0ae8eb6c8fc15620f --gateway-id vgw-033d62a759c784184
```

SG 는 **인스턴스가 완전히 종료된 뒤에야** 지워진다. 바로 실패하면 1~2분 기다린다.

```bash
aws ec2 delete-security-group --region ap-northeast-2 --group-id <BASTION_SG>
```

```bash
aws ec2 delete-key-pair --region ap-northeast-2 --key-name boa-bastion
```

로컬의 `%USERPROFILE%\.ssh\boa-bastion.pem` 도 함께 지운다.

> 가운데 두 명령은 **Terraform 에 없는 변경**을 되돌리는 것이다.
> 지우지 않으면 코드와 실제가 어긋난 채 남고, 나중에 `aws-rds` apply 때 조용히 되돌아가
> "어제까진 됐는데"가 된다.

---

## 남기는 것

| 자원 | 이유 |
|---|---|
| `dms-vpc-role` · `dms-cloudwatch-logs-role` | 이름 고정, 계정·리전 공용 |
| VPN (`net-link`) | 터널 재수립이 느리다. DR 리허설마다 걷지 않는다 |
| `gcp-core` · `aws-core` | 네트워크 기반 |

## 완료 확인

```bash
aws dms describe-replication-tasks --region ap-northeast-2 --query "length(ReplicationTasks)"
```

```bash
aws dms describe-endpoints --region ap-northeast-2 --query "length(Endpoints)"
```

```bash
aws dms describe-replication-instances --region ap-northeast-2 --query "length(ReplicationInstances)"
```

세 개 다 `0` 이면 DMS 는 정리된 것이다.

```bash
aws rds describe-db-instances --region ap-northeast-2 --query "DBInstances[].DBInstanceIdentifier" --output text
```

```bash
gcloud sql instances list
```

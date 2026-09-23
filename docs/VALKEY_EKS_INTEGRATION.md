# AWS EKS Valkey 연동 변경 가이드

## 1. 목적과 범위

Bank of Anthos 서비스 앱 6개가 ElastiCache Serverless Valkey를 다음 용도로 사용할 수 있도록 AWS 아키텍처 코드를 변경한다.

- `frontend`: 서버 측 로그인 세션
- `userservice`: 회원가입 중복 처리 락
- `contacts`: 연락처 조회 캐시
- `balancereader`: 잔액 조회 캐시
- `ledgerwriter`: 잔액·거래내역 캐시 무효화
- `transactionhistory`: 거래내역 조회 캐시

변경 저장소는 `Infra`와 `gitops`뿐이다. `frontend`, `accounts`, `ledger` 애플리케이션 소스, CI, ECR 이름·태그 규칙, GCP 코드는 변경하지 않는다.

이 작업에서는 Terraform `apply`, Kubernetes 배포, Route53 변경을 실행하지 않았다.

## 2. 최종 구조

```text
/boa/valkey/credentials (운영자 관리)
  ├─ username = redis
  └─ password
            │
            ▼
aws-cache Terraform ──> ElastiCache RBAC User / User Group / Serverless Cache
            │
            └─ cache endpoint
                    │
                    ▼
        /boa/valkey/runtime (Terraform 관리)
          └─ host

/boa/valkey/credentials + /boa/valkey/runtime
                    │
                    ▼
Secrets Store CSI Provider
                    │
                    ▼
Kubernetes Secret: valkey-secret
  ├─ host
  ├─ username
  └─ password
                    │
                    ▼
                 앱 6개
```

고정 설정은 Secrets Manager에 저장하지 않고 앱 Deployment에 둔다.

```text
VALKEY_PORT=6379
VALKEY_TLS=true
VALKEY_CLUSTER_MODE=true  # Python 앱 3개만
```

## 3. Terraform 변경

### `aws-cache/main.tf`

변경 내용:

- `data.aws_secretsmanager_secret.valkey_credentials`로 `/boa/valkey/credentials` 조회
- `data.aws_secretsmanager_secret_version.valkey_credentials`로 `AWSCURRENT` 값 조회
- JSON의 `username`, `password`를 ElastiCache 모듈 입력으로 전달
- 캐시 endpoint의 `address`를 `/boa/valkey/runtime` Secret Version에 `host`로 저장
- runtime Secret에 `recovery_window_in_days = 0` 적용

이유:

- 운영자가 만든 credentials를 단일 원본으로 사용한다.
- Terraform이 비밀번호를 새로 만들거나 기존 credentials Secret을 소유하지 않게 한다.
- 캐시 교체로 endpoint가 변경돼도 GitOps YAML을 직접 수정하지 않고 CSI 경로로 전달한다.

의존성은 한 방향이다.

```text
aws-core remote state → aws-cache → runtime Secret → CSI → 앱
```

`aws-modules/elasticache`는 별도 State가 아니다. 해당 모듈 리소스도 `aws-cache` State 안에 저장된다.

### `aws-cache/outputs.tf`

변경 내용:

- 기존 `secret_arn` 출력 이름은 호환성을 위해 유지하되 외부 credentials Secret ARN을 반환
- `runtime_secret_arn` 출력 추가

### `aws-cache/versions.tf`, `aws-cache/.terraform.lock.hcl`

변경 내용:

- `hashicorp/random` Provider 요구사항과 Lock 항목 제거

이유:

- Terraform이 더 이상 Valkey 비밀번호를 생성하지 않는다.

### `aws-modules/elasticache/main.tf`

제거한 리소스:

- `random_password.valkey`
- `aws_secretsmanager_secret.valkey`
- `aws_secretsmanager_secret_version.valkey`

변경 내용:

- RBAC 사용자는 호출자가 전달한 `user_name`, `user_password` 사용
- ACL은 기존 `on ~* +@all` 유지
- `create_before_destroy = true` 추가

이유:

- credentials의 실제 소유자는 계속 운영자다. Secrets Manager 조회와 모듈 연결 책임만 재사용 모듈에서 환경 root인 `aws-cache`로 이동한다.
- 기존 `boa-app` 사용자에서 Secret의 `redis` 사용자로 바뀔 때 새 사용자를 먼저 만들고 User Group을 전환한다.

### `aws-modules/elasticache/variables.tf`, `outputs.tf`

변경 내용:

- 민감한 `user_password` 입력 추가
- 모듈이 더 이상 소유하지 않는 `secret_arn` 출력 제거

### `aws-modules/elasticache/security.tf`

변경 내용:

- 캐시 보안 그룹 인바운드 범위를 TCP `6379`에서 `6379-6380`으로 변경
- 허용 출발지는 기존 EKS private subnet CIDR만 유지

이유:

- ElastiCache Serverless는 primary 연결에 6379, read endpoint 연결에 6380을 사용한다.
- VPC 전체나 인터넷 전체를 열지 않는다.

## 4. GitOps 공통 Secret 변경

두 위치에 같은 구성을 반영했다.

- 최초 수동 배포본: `manual/eks`
- Argo CD 정본: `03_manifests/eks`

한쪽만 변경하면 최초 배포와 Argo CD 인수 이후 상태가 달라지므로 반드시 함께 유지한다.

### `03_manifests/eks/shared/secrets.yaml`
### `manual/eks/secrets.yaml`

`bank-of-anthos-valkey-secrets` SecretProviderClass를 추가했다.

읽는 원본:

- `/boa/valkey/credentials`: `username`, `password`
- `/boa/valkey/runtime`: `host`

생성하는 Kubernetes Secret:

```text
valkey-secret
  ├─ host
  ├─ username
  └─ password
```

DB/JWT SecretProviderClass에 Valkey를 섞지 않고 별도 리소스로 두어 책임과 장애 범위를 분리했다.

### `03_manifests/eks/shared/secret-sync.yaml`
### `manual/eks/secret-sync.yaml`

변경 내용:

- Valkey SecretProviderClass용 CSI volume과 mount 추가
- host, username, password 파일 존재 검사 추가

이유:

- CSI의 `secretObjects`는 해당 SecretProviderClass를 Pod가 마운트할 때 Kubernetes Secret을 생성한다.
- 앱이 `valkey-secret`을 참조하기 전에 secret-sync가 이를 생성해 시작 순환을 끊는다.

## 5. 앱 Deployment 변경

### GitOps 정본

- `03_manifests/eks/frontend/frontend.yaml`
- `03_manifests/eks/accounts/userservice.yaml`
- `03_manifests/eks/accounts/contacts.yaml`
- `03_manifests/eks/ledger/balancereader.yaml`
- `03_manifests/eks/ledger/ledgerwriter.yaml`
- `03_manifests/eks/ledger/transactionhistory.yaml`

### 최초 수동 배포본

- `manual/eks/frontend.yaml`
- `manual/eks/userservice.yaml`
- `manual/eks/contacts.yaml`
- `manual/eks/balancereader.yaml`
- `manual/eks/ledgerwriter.yaml`
- `manual/eks/transactionhistory.yaml`

모든 앱에 추가한 값:

```yaml
VALKEY_HOST: valkey-secret/host
VALKEY_PORT: "6379"
VALKEY_USERNAME: valkey-secret/username
VALKEY_PASSWORD: valkey-secret/password
VALKEY_TLS: "true"
```

Python 앱인 `frontend`, `userservice`, `contacts`에는 다음도 추가했다.

```yaml
VALKEY_CLUSTER_MODE: "true"
```

Java 앱 3개는 코드에서 항상 cluster client를 사용하므로 이 환경변수를 추가하지 않았다.

## 6. NetworkPolicy 변경

### GitOps 정본

- `03_manifests/eks/frontend/kustomization.yaml`
- `03_manifests/eks/accounts/kustomization.yaml`
- `03_manifests/eks/ledger/kustomization.yaml`

### 최초 수동 배포본

- 앱별 `manual/eks/*.yaml`의 NetworkPolicy

추가한 egress:

```text
목적지: 192.168.24.0/24, 192.168.25.0/24
포트: TCP 6379, TCP 6380
```

기존 DB, 내부 서비스, DNS egress는 유지했다.

## 7. frontend HTTPS 변경

### `03_manifests/eks/frontend/ingress.yaml`
### `manual/eks/ingress.yaml`

변경 내용:

- ALB Listener에 HTTP 80과 HTTPS 443 설정
- 기존 `*.bespinglobal.site` ACM 인증서 연결
- HTTP 요청을 HTTPS 443으로 전환
- `spec.rules.host`는 추가하지 않음

Ingress가 host를 제한하지 않으므로 ALB까지 도착한 요청을 frontend로 전달한다. TLS는 ALB에서 종료되고 ALB에서 frontend Pod로는 기존 HTTP 8080을 사용한다.

### frontend Deployment

```text
SCHEME=https
COOKIE_SECURE=true
```

`SCHEME=https`는 frontend가 브라우저용 외부 URL을 HTTPS로 생성하게 한다. `COOKIE_SECURE=true`와 앱의 `__Host-boa_session` 쿠키는 사용자와 ALB 사이 HTTPS를 요구한다.

## 8. Route53 수동 작업

Terraform은 frontend Route53 레코드를 관리하지 않는다.

Ingress 적용 후 생성된 서비스 ALB를 확인하고 Route53 콘솔에서 기존 레코드를 점검한다.

```text
레코드 이름: app.bespinglobal.site
레코드 유형: A
Alias: 활성화
대상: 현재 EKS 서비스 ALB
```

ALB의 개별 IP를 A 레코드에 직접 입력하지 않는다. ALB가 교체되면 Alias 대상도 수동으로 갱신한다.

## 9. 검토 후 적용 순서

1. `/boa/valkey/credentials`의 `AWSCURRENT`가 `username`, `password` JSON 키를 가지며 `username`이 정확히 `redis`인지 콘솔에서 확인한다. 비밀번호는 출력하거나 문서에 복사하지 않는다.
2. 기존 State가 추적하는 옛 Secret ARN을 `terraform state show module.elasticache.aws_secretsmanager_secret.valkey`로 확인한다. 이 명령은 State를 변경하지 않는다.
3. 콘솔에서 새로 만든 `/boa/valkey/credentials`의 ARN과 2번의 옛 ARN이 다른지 확인한다. 이번 환경은 옛 Secret을 삭제한 뒤 새로 생성했으므로 ARN이 달라야 한다.
4. `aws-cache`에서 `terraform plan`을 실행한다. refresh가 존재하지 않는 옛 ARN을 State에서 제거하고 새 Secret은 data source로만 읽는지 확인한다.
5. 계획에 현재 수동 credentials Secret 또는 그 Secret Version 삭제가 표시되면 apply하지 말고 팀 검토를 요청한다. 이 경우에만 별도 State 분리 절차가 필요하다.
6. ElastiCache 사용자 교체, SG 6380 추가, runtime Secret 생성만 의도대로 표시되는지 확인한다.
7. 팀 검토 후 `aws-cache`를 apply한다.
8. `/boa/valkey/runtime`에 현재 cache endpoint의 `host`가 생겼는지 확인한다. 값을 문서나 로그에 복사하지 않는다.
9. 최초 배포면 `manual/eks`, Argo CD 운영 중이면 shared → accounts/ledger → frontend 순서로 동기화한다.
10. 서비스 ALB 생성 후 Route53 Alias 대상을 확인한다.

## 10. 캐시 교체 후 수동 Secret 갱신

CSI 자동 회전은 이번 범위에 포함하지 않았다. 캐시 교체로 runtime host가 변경되면 다음 순서로 수동 rollout한다.

```powershell
kubectl -n bank-of-anthos rollout restart deployment/bank-of-anthos-secret-sync
kubectl -n bank-of-anthos rollout status deployment/bank-of-anthos-secret-sync

kubectl -n bank-of-anthos rollout restart deployment/frontend deployment/userservice deployment/contacts deployment/balancereader deployment/ledgerwriter deployment/transactionhistory
kubectl -n bank-of-anthos rollout status deployment/frontend
kubectl -n bank-of-anthos rollout status deployment/userservice
kubectl -n bank-of-anthos rollout status deployment/contacts
kubectl -n bank-of-anthos rollout status deployment/balancereader
kubectl -n bank-of-anthos rollout status deployment/ledgerwriter
kubectl -n bank-of-anthos rollout status deployment/transactionhistory
```

Secret 값은 출력하지 않는다. 키 존재만 확인하려면 다음처럼 조회한다.

```powershell
kubectl -n bank-of-anthos get secret valkey-secret -o go-template='{{range $key, $value := .data}}{{$key}}{{"\n"}}{{end}}'
```

기대 키:

```text
host
password
username
```

## 11. 검증 명령

Terraform 검증:

```powershell
terraform fmt -check -recursive aws-cache aws-modules/elasticache
terraform -chdir=aws-cache init -backend=false
terraform -chdir=aws-cache validate
```

Kustomize 검증:

```powershell
kubectl kustomize 03_manifests/eks/shared
kubectl kustomize 03_manifests/eks/accounts
kubectl kustomize 03_manifests/eks/ledger
kubectl kustomize 03_manifests/eks/frontend
kubectl kustomize manual/eks
```

이 변경 작업에서 위 Terraform validate와 Kustomize 5개 렌더링은 로컬에서 통과했다. 실제 AWS plan/apply와 실제 클러스터 배포 검증은 수행하지 않았다.

## 12. 롤백과 주의사항

- 앱 장애 시 GitOps 변경을 이전 커밋으로 되돌릴 수 있다. Valkey 인프라는 남아 있어도 기존 앱 동작에는 영향이 없다.
- 기존 랜덤 비밀번호 코드를 단순히 되돌리면 수동 `/boa/valkey/credentials`와 이름이 충돌할 수 있다. Terraform 쪽 롤백은 plan과 State를 팀이 함께 확인한 후 진행한다.
- `/boa/valkey/runtime`은 endpoint만 가지며 `aws-cache` destroy 시 즉시 삭제된다.
- 현재 설계는 `/boa/valkey/credentials` 비밀번호가 변경되지 않는다는 전제다. 단일 ElastiCache 비밀번호를 사용하므로 향후 자격증명을 회전하려면 유지보수 시간에 Terraform 변경, secret-sync 재시작, 앱 6개 rollout을 연속 수행해야 한다. 무중단 회전이 필요해지면 ElastiCache의 두 비밀번호를 이용하는 별도 전환 설계를 먼저 추가한다.
- credentials 비밀번호는 `aws_elasticache_user` 입력이므로 Terraform State에 민감 정보로 저장될 수 있다. 기존 S3 State 접근권한과 암호화 정책을 유지해야 한다.
- 여섯 앱은 같은 `redis` 계정과 `on ~* +@all` 권한을 공유한다. 팀 과제 범위의 단순성을 위한 선택이며, 서비스별 사용자와 키 패턴 분리는 후속 보안 개선 사항이다.
- `03_manifests/gke`, `03_manifests/base`, GCP Terraform 코드는 변경하지 않는다.

# AWS Valkey 통합 코드 변경 목록

## 1. 문서 기준

- 기준 브랜치: `dev`
- 작업 브랜치: `feature/aws-valkey-runtime-integration`
- 대상 저장소: `Infra`, `gitops`
- 제외 범위: `frontend`, `accounts`, `ledger` 앱 소스와 모든 GCP/GKE 코드
- 1차 작업: Valkey endpoint·credentials를 EKS 앱 6개에 전달하고 HTTPS·네트워크 경로 구성
- 2차 작업: 수동 credentials 조회를 Terraform ephemeral/write-only 생성 방식으로 변경

최종 데이터 흐름은 다음과 같다.

```text
ephemeral random password
  ├─> /boa/valkey/credentials (Secrets Manager, write-only 저장)
  └─> ElastiCache User redis (write-only 전달)

ElastiCache endpoint
  └─> /boa/valkey/runtime

credentials + runtime
  └─> Secrets Store CSI -> valkey-secret -> 앱 6개
```

## 2. Infra 저장소 변경

### 2.1 `aws-cache/main.tf`

#### 1차 작업에서 추가했다가 2차 작업에서 삭제한 코드

```hcl
# 기능/이유: 콘솔에서 만든 credentials Secret과 현재 값을 읽기 위한 중간 설계였다.
data "aws_secretsmanager_secret" "valkey_credentials" {
  name = "/boa/valkey/credentials"
}

data "aws_secretsmanager_secret_version" "valkey_credentials" {
  secret_id     = data.aws_secretsmanager_secret.valkey_credentials.id
  version_stage = "AWSCURRENT"
}

locals {
  valkey_credentials = jsondecode(data.aws_secretsmanager_secret_version.valkey_credentials.secret_string)
}
```

삭제 이유: 운영자의 수동 Secret 생성 절차를 없애고 비밀번호를 Terraform State에 남기지 않는 방식으로 통일했다.

#### 2차 작업에서 추가한 credentials 버전과 ephemeral 비밀번호

```hcl
# 기능/이유: 이 숫자 하나로 Secrets Manager와 ElastiCache의 비밀번호 갱신 시점을 맞춘다.
locals {
  valkey_credentials_version = 1
}

# 기능/이유: 실행 중에만 32자리 비밀번호를 생성하여 plan/state에 평문을 남기지 않는다.
ephemeral "random_password" "valkey" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}
```

#### 2차 작업에서 추가한 credentials Secret

```hcl
# 기능/이유: `/boa/valkey/credentials`의 생성과 삭제를 aws-cache State가 관리한다.
resource "aws_secretsmanager_secret" "valkey_credentials" {
  name                    = "/boa/valkey/credentials"
  recovery_window_in_days = 0
  tags = {
    Name = "boa-valkey-credentials"
  }
}

# 기능/이유: redis 사용자명과 ephemeral 비밀번호를 write-only로 저장해 State 노출을 막는다.
resource "aws_secretsmanager_secret_version" "valkey_credentials" {
  secret_id = aws_secretsmanager_secret.valkey_credentials.id
  secret_string_wo = jsonencode({
    username = "redis"
    password = ephemeral.random_password.valkey.result
  })
  secret_string_wo_version = local.valkey_credentials_version
}
```

#### ElastiCache 모듈 입력 변경

삭제된 최종 이전 코드:

```hcl
# 기능/이유: 외부 Secret을 읽어 모듈에 넘기던 방식이므로 ephemeral 전환 후 제거했다.
cache_name    = "boa-valkey"
user_name     = local.valkey_credentials.username
user_password = local.valkey_credentials.password
```

추가된 최종 코드:

```hcl
# 기능/이유: 사용자명은 redis로 고정하고 동일한 ephemeral 값을 Valkey에도 직접 전달한다.
cache_name          = "boa-valkey"
user_name           = "redis"
user_password       = ephemeral.random_password.valkey.result
credentials_version = local.valkey_credentials_version

# 기능/이유: credentials 저장이 완료된 뒤 같은 값으로 Valkey 사용자를 갱신한다.
depends_on = [
  aws_secretsmanager_secret_version.valkey_credentials
]
```

#### 1차 작업에서 추가한 runtime Secret

```hcl
# 기능/이유: 캐시가 재생성되어 endpoint가 바뀌어도 앱 YAML을 수정하지 않고 CSI로 전달한다.
resource "aws_secretsmanager_secret" "valkey_runtime" {
  name                    = "/boa/valkey/runtime"
  recovery_window_in_days = 0
  tags = {
    Name = "boa-valkey-runtime"
  }
}

# 기능/이유: list(object)인 Serverless endpoint의 첫 주소를 host 키로 저장한다.
resource "aws_secretsmanager_secret_version" "valkey_runtime" {
  secret_id = aws_secretsmanager_secret.valkey_runtime.id
  secret_string = jsonencode({
    host = module.elasticache.cache_endpoint[0].address
  })
}
```

초기에는 `module.elasticache.cache_endpoint.address`를 사용했으나 실제 plan에서 endpoint가 리스트임을 확인하여 `[0].address`로 수정했다.

### 2.2 `aws-cache/outputs.tf`

삭제:

```hcl
# 기능/이유: credentials Secret이 모듈 소유였을 때 사용하던 출력이라 제거했다.
value = module.elasticache.secret_arn
```

중간 설계에서 사용 후 삭제:

```hcl
# 기능/이유: 외부 수동 Secret ARN을 반환하던 값으로 Terraform 관리 전환 후 제거했다.
value = data.aws_secretsmanager_secret.valkey_credentials.arn
```

최종 추가:

```hcl
# 기능/이유: 출력 이름은 유지하면서 Terraform이 관리하는 credentials ARN을 반환한다.
output "secret_arn" {
  description = "Terraform-managed Valkey credentials Secret ARN"
  value       = aws_secretsmanager_secret.valkey_credentials.arn
}

# 기능/이유: endpoint를 보관하는 runtime Secret ARN을 외부 검증에 제공한다.
output "runtime_secret_arn" {
  description = "Terraform-managed Valkey runtime endpoint Secret ARN"
  value       = aws_secretsmanager_secret.valkey_runtime.arn
}
```

### 2.3 `aws-cache/versions.tf`

변경:

```hcl
# 기능/이유: write-only 인수 지원을 위해 Terraform 최소 버전을 1.11로 올린다.
required_version = ">= 1.11.0"

# 기능/이유: ephemeral random_password를 제공하는 Random Provider 3.7 이상을 사용한다.
random = {
  source  = "hashicorp/random"
  version = "~> 3.7"
}
```

1차 작업에서는 일반 `random_password`를 제거하면서 Random Provider도 제거했지만, 2차 작업에서 ephemeral 생성용으로 다시 추가했다.

### 2.4 `aws-cache/.terraform.lock.hcl`

- 삭제·추가: 1차 작업에서 `hashicorp/random` Lock을 제거했고, 2차 작업에서 `hashicorp/random v3.9.1` Lock과 플랫폼 해시를 다시 추가했다.
- 기능/이유: 팀원이 같은 Provider 바이너리 버전을 재현하도록 Terraform이 자동 관리한다.

### 2.5 `aws-modules/elasticache/main.tf`

1차 작업에서 모듈로부터 삭제:

```hcl
# 기능/이유: 일반 랜덤 비밀번호가 State에 저장되므로 모듈 내부 생성을 제거했다.
resource "random_password" "valkey" {
  length  = 32
  special = false
}

# 기능/이유: 재사용 모듈이 환경별 Secret까지 소유하지 않도록 root 모듈로 책임을 옮겼다.
resource "aws_secretsmanager_secret" "valkey" {
  name                    = "/${var.project_name}/valkey/credentials"
  recovery_window_in_days = 0
}

# 기능/이유: 일반 secret_string에 비밀번호가 저장되던 경로를 제거했다.
resource "aws_secretsmanager_secret_version" "valkey" {
  secret_id = aws_secretsmanager_secret.valkey.id
  secret_string = jsonencode({
    username = var.user_name
    password = random_password.valkey.result
  })
}
```

2차 작업에서 삭제:

```hcl
# 기능/이유: 일반 passwords 인수가 비밀번호를 State에 저장하므로 제거했다.
authentication_mode {
  type      = "password"
  passwords = [var.user_password]
}
```

2차 작업에서 추가:

```hcl
# 기능/이유: 비밀번호와 버전만 AWS API에 전달하고 State에는 저장하지 않는다.
passwords_wo         = var.user_password
passwords_wo_version = var.credentials_version

# 기능/이유: user_id가 바뀌는 경우 기존 사용자 삭제보다 새 사용자 생성을 먼저 시도한다.
lifecycle {
  create_before_destroy = true
}
```

ACL `on ~* +@all`, User Group, Serverless Cache 리소스는 유지했다.

### 2.6 `aws-modules/elasticache/variables.tf`

1차 작업에서 추가한 뒤 2차 작업에서 강화:

```hcl
# 기능/이유: root가 만든 비밀번호를 모듈에 전달하되 로그 표시와 State 저장을 모두 막는다.
variable "user_password" {
  type      = string
  sensitive = true
  ephemeral = true
}

# 기능/이유: ElastiCache write-only 비밀번호 변경 여부를 명시적으로 관리한다.
variable "credentials_version" {
  type = number
}
```

주석 변경:

```hcl
# 기능/이유: Serverless Valkey의 primary/read 연결에 필요한 전체 포트 범위를 명시한다.
# Serverless Valkey 6379-6380 인바운드를 허용할 프라이빗 서브넷 CIDR
```

### 2.7 `aws-modules/elasticache/security.tf`

삭제:

```hcl
# 기능/이유: 6379 하나만 허용하면 Serverless read endpoint 6380 통신이 막힌다.
to_port = 6379
```

추가:

```hcl
# 기능/이유: EKS private subnet에서 primary 6379와 read 6380만 허용한다.
from_port = 6379
to_port   = 6380
```

설명과 Name 태그도 `6379-6380`으로 변경했다. 허용 CIDR은 기존 EKS private subnet으로 제한했다.

### 2.8 `aws-modules/elasticache/outputs.tf`

삭제:

```hcl
# 기능/이유: 모듈이 credentials Secret을 더 이상 소유하지 않으므로 이 출력도 제거했다.
output "secret_arn" {
  value = aws_secretsmanager_secret.valkey.arn
}
```

### 2.9 Infra 문서

- `docs/VALKEY_EKS_INTEGRATION.md`: 전체 구조, 적용 순서, 검증, 롤백 절차를 기록했다.
- `docs/VALKEY_CHANGE_CATALOG.md`: 두 차례 작업의 파일별 삭제·추가 코드와 이유를 기록한 현재 문서다.

## 3. gitops 저장소 변경

### 3.1 Valkey SecretProviderClass

적용 파일:

- `03_manifests/eks/shared/secrets.yaml`
- `manual/eks/secrets.yaml`

추가 코드:

```yaml
# 기능/이유: AWS credentials와 runtime Secret을 하나의 Kubernetes Secret으로 동기화한다.
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: bank-of-anthos-valkey-secrets
spec:
  provider: aws
  parameters:
    usePodIdentity: "true"
    objects: |
      - objectName: "/boa/valkey/credentials"
        objectType: "secretsmanager"
        jmesPath:
          - path: username
            objectAlias: valkey-username
          - path: password
            objectAlias: valkey-password
      - objectName: "/boa/valkey/runtime"
        objectType: "secretsmanager"
        jmesPath:
          - path: host
            objectAlias: valkey-host
  secretObjects:
    - secretName: valkey-secret
      type: Opaque
      data:
        - objectName: valkey-host
          key: host
        - objectName: valkey-username
          key: username
        - objectName: valkey-password
          key: password
```

2차 작업에서는 주석의 소유 주체를 `운영자 관리`에서 `aws-cache Terraform 관리`로 바로잡았다. 리소스 구조는 변경하지 않았다.

### 3.2 secret-sync에 Valkey CSI mount 추가

적용 파일:

- `03_manifests/eks/shared/secret-sync.yaml`
- `manual/eks/secret-sync.yaml`

추가 코드:

```yaml
# 기능/이유: 앱이 시작하기 전에 CSI mount로 valkey-secret 생성을 유도하고 세 키 존재를 검사한다.
test -s /mnt/valkey-secrets/valkey-host
test -s /mnt/valkey-secrets/valkey-username
test -s /mnt/valkey-secrets/valkey-password

- name: valkey-secrets-store
  mountPath: /mnt/valkey-secrets
  readOnly: true

- name: valkey-secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: bank-of-anthos-valkey-secrets
```

### 3.3 앱 6개에 공통 Valkey 환경변수 추가

GitOps 정본 파일:

- `03_manifests/eks/frontend/frontend.yaml`
- `03_manifests/eks/accounts/userservice.yaml`
- `03_manifests/eks/accounts/contacts.yaml`
- `03_manifests/eks/ledger/balancereader.yaml`
- `03_manifests/eks/ledger/ledgerwriter.yaml`
- `03_manifests/eks/ledger/transactionhistory.yaml`

최초 수동 배포 파일:

- `manual/eks/frontend.yaml`
- `manual/eks/userservice.yaml`
- `manual/eks/contacts.yaml`
- `manual/eks/balancereader.yaml`
- `manual/eks/ledgerwriter.yaml`
- `manual/eks/transactionhistory.yaml`

공통 추가 코드:

```yaml
# 기능/이유: host·username·password는 Kubernetes Secret에서, 고정 연결 옵션은 manifest에서 주입한다.
- name: VALKEY_HOST
  valueFrom:
    secretKeyRef:
      name: valkey-secret
      key: host
- name: VALKEY_PORT
  value: "6379"
- name: VALKEY_USERNAME
  valueFrom:
    secretKeyRef:
      name: valkey-secret
      key: username
- name: VALKEY_PASSWORD
  valueFrom:
    secretKeyRef:
      name: valkey-secret
      key: password
- name: VALKEY_TLS
  value: "true"
```

Python 앱 `frontend`, `userservice`, `contacts`에만 추가:

```yaml
# 기능/이유: Python Valkey 클라이언트가 Serverless cluster topology를 사용하게 한다.
- name: VALKEY_CLUSTER_MODE
  value: "true"
```

Java 앱 3개는 코드 자체가 cluster client를 사용하므로 해당 변수를 추가하지 않았다.

### 3.4 Valkey egress NetworkPolicy 추가

GitOps 정본 파일:

- `03_manifests/eks/frontend/kustomization.yaml`
- `03_manifests/eks/accounts/kustomization.yaml`
- `03_manifests/eks/ledger/kustomization.yaml`

최초 수동 배포에서는 다음 파일의 앱별 NetworkPolicy에 직접 추가했다.

- `manual/eks/frontend.yaml`
- `manual/eks/userservice.yaml`
- `manual/eks/contacts.yaml`
- `manual/eks/balancereader.yaml`
- `manual/eks/ledgerwriter.yaml`
- `manual/eks/transactionhistory.yaml`

추가 코드:

```yaml
# 기능/이유: 앱 Pod가 cache subnet A/C의 Serverless Valkey 6379·6380으로만 나가도록 허용한다.
- to:
    - ipBlock:
        cidr: 192.168.24.0/24
    - ipBlock:
        cidr: 192.168.25.0/24
  ports:
    - port: 6379
      protocol: TCP
    - port: 6380
      protocol: TCP
```

기존 DB, DNS, 내부 서비스 egress는 삭제하지 않았다.

### 3.5 frontend HTTPS와 세션 쿠키

Ingress 적용 파일:

- `03_manifests/eks/frontend/ingress.yaml`
- `manual/eks/ingress.yaml`

삭제:

```yaml
# 기능/이유: HTTP 80만 열면 Secure 세션 쿠키를 정상 사용할 수 없어 교체했다.
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
```

추가:

```yaml
# 기능/이유: ALB가 HTTP와 HTTPS를 받고 HTTP 요청은 인증서가 연결된 443으로 전환한다.
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-northeast-2:769413326616:certificate/1c81ee2e-edbc-4a42-961d-816d571767ab
alb.ingress.kubernetes.io/ssl-redirect: "443"
```

`spec.rules.host`는 기존부터 없었으며 이번에도 추가하지 않았다. ALB에서 TLS를 종료하고 Pod에는 기존 HTTP 8080으로 전달한다.

frontend 적용 파일:

- `03_manifests/eks/frontend/frontend.yaml`
- `manual/eks/frontend.yaml`

삭제·추가:

```yaml
# 삭제: 외부 URL을 HTTP로 생성하던 설정이다.
- name: SCHEME
  value: "http"

# 추가 기능/이유: 외부 URL을 HTTPS로 만들고 세션 쿠키를 HTTPS에서만 전송한다.
- name: SCHEME
  value: "https"
- name: COOKIE_SECURE
  value: "true"
```

GitOps overlay에는 기존 `SCHEME` 값이 없어서 `https` 항목을 새로 추가했고, 수동 manifest에서는 `http`를 `https`로 교체했다.

## 4. 삭제·변경하지 않은 영역

- 서비스 앱 소스 저장소 `frontend`, `accounts`, `ledger`
- 이미지 이름과 ECR 태그
- `03_manifests/gke`, `03_manifests/base`
- GCP Terraform 코드
- DB/JWT SecretProviderClass
- ALB에서 frontend Pod로 가는 HTTP 8080 통신
- Route53 Terraform 리소스: `app.bespinglobal.site` Alias는 수동 관리

## 5. AWS에서 수행한 수동 작업

- 기존 수동 `/boa/valkey/credentials` 하나를 정확한 ARN으로 `force-delete-without-recovery` 삭제했다.
- 다른 Secret에는 삭제 API를 호출하지 않았다.
- `/boa/valkey/runtime`은 존재하지 않는 것을 확인했다.
- 삭제된 credentials Secret은 복구할 수 없으며, 다음 apply에서 Terraform이 같은 이름으로 새로 생성한다.

## 6. 검증 결과

- Terraform `fmt -check`: 통과
- Terraform `validate`: 통과
- AWS 계정과 실제 S3 remote state 기반 `terraform plan`: 통과
- 최종 plan: `4 add, 2 change, 0 destroy`
- credentials 비밀번호 표시: `(write-only attribute)`로 비노출
- Kustomize 렌더링: `shared`, `accounts`, `ledger`, `frontend`, `manual/eks` 통과
- `git diff --check`: 통과
- GCP/GKE 및 앱 소스 변경 없음

## 7. 적용 전후 확인사항

1. apply 직전에 `terraform plan`을 다시 실행해 `0 destroy`인지 확인한다.
2. apply 후 `/boa/valkey/credentials`에 `username`, `password` 키가 있고 username이 `redis`인지 확인한다.
3. apply 후 `/boa/valkey/runtime`에 `host` 키가 생성됐는지 확인한다.
4. secret-sync를 재시작한 뒤 앱 6개를 rollout한다.
5. `valkey-secret`은 값이 아니라 `host`, `username`, `password` 키 존재만 확인한다.
6. `https://app.bespinglobal.site` 로그인과 세션 유지, 각 앱의 Valkey 연결을 확인한다.
7. 향후 비밀번호 변경은 `valkey_credentials_version`을 올리고 Terraform apply와 앱 rollout을 같은 유지보수 시간에 수행한다.

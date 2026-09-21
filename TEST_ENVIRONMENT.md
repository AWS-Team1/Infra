# Valkey 검증용 AWS 테스트 환경

기존 `aws-*` Terraform root와 기존 VPC를 변경하지 않고 같은 AWS 계정에 독립 환경을 만든다.

## 격리 기준

| 항목 | 테스트 환경 값 |
| --- | --- |
| 리소스 접두사 | `boa-test` |
| VPC | `boa-test-vpc` (`10.0.0.0/16`) |
| Public subnet | `10.0.2.0/24`, `10.0.3.0/24` |
| EKS subnet | `10.0.8.0/24`, `10.0.9.0/24` |
| RDS subnet | `10.0.16.0/24`, `10.0.17.0/24` |
| Valkey subnet | `10.0.24.0/24`, `10.0.25.0/24` |
| EKS | `boa-test-eks` |
| RDS | `boa-test-postgres` |
| DB DNS | `db.test.boa.internal` |
| Valkey | `boa-test-valkey`, user `boa-test-app` |
| Secrets Manager | `/boa-test/*` |
| Terraform state | `aws/test/*/terraform.tfstate` |
| ECR | `boa-test-<service>` |

Kubernetes namespace는 클러스터 자체가 분리되므로 기존과 같은 `bank-of-anthos`를 사용한다.

## 사전 작업

Valkey Secret은 Terraform보다 먼저 AWS Console에서 직접 생성한다. Secret 이름은
`/boa-test/valkey/credentials`, 값은 아래 JSON 형식이며 username은 Terraform 설정과 반드시 같아야 한다.

```json
{
  "username": "boa-test-app",
  "password": "직접 정한 16자 이상의 비밀번호"
}
```

비밀번호를 명령행 인자에 직접 넣으면 shell history와 프로세스 목록에 노출될 수 있으므로 피한다.

## 적용 순서

각 디렉터리에서 `terraform init`, `terraform plan`, `terraform apply`를 순서대로 수행한다.

1. `aws-test-core`
2. `aws-test-rds`, `aws-test-cache`, `aws-test-eks`, `aws-test-ops`
3. `aws-test-db-bootstrap`
4. `scripts/prepare-test-secrets.sh`로 기존 DB/JWT 값을 테스트 Secret에 복사
5. DB bootstrap Job과 `gitops/03_manifests/eks-test` 적용
6. `scripts/configure-test-runtime.sh`로 실제 ElastiCache endpoint를 ConfigMap에 반영

`aws-test-ops`가 만드는 ECR은 처음에는 비어 있다. 애플리케이션 변경 후 여섯 이미지를
`boa-test-<service>` 저장소에 빌드·push하고 테스트 manifest의 tag를 그 값으로 바꾼 뒤 배포한다.

`aws-test-cache`는 Secrets Manager 값을 ephemeral resource로 읽고 ElastiCache의 write-only
`passwords_wo`에 전달한다. 비밀번호를 교체하면 `credentials_version`도 증가시킨다.
Valkey는 TLS 인증서의 호스트명 검증을 유지하기 위해 별칭 CNAME이 아니라 AWS가 발급한 endpoint를 사용한다.

두 NAT Gateway와 EKS/RDS/Valkey는 실행 중 비용이 발생한다. 검증 종료 후에는 위 순서의 역순으로
테스트 root만 destroy한다. 운영 root의 state를 테스트 root 명령에 사용하면 안 된다.

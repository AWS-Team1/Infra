# Terraform 루트 분리 설계

- 작성일: 2026-09-14
- 대상 저장소: `swoobuntu/Infra` (브랜치 `Karfa-choi`)
- 선행 커밋: `97a01b6` (boa- 접두사 전환, 기존 VPC 재사용)

## 1. 배경

현재 `Infra/`는 **단일 루트 모듈**이다. 루트 `main.tf`가 모듈 6종을 호출하고 state 하나가 전부를 담는다.

문제는 셋이다.

1. **작업이 직렬화된다.** 누가 apply하면 state 락이 전체를 잠근다. RDS apply는 십수 분 걸린다.
2. **provider가 섞여 있다.** `provider.tf`의 kubernetes·helm이 `module.eks` 출력에 의존해, 클러스터가 없으면 `plan`조차 돌지 않는다.
3. **폭발 반경이 하나다.** 서브넷 하나 고치는 plan에 RDS 변경이 같이 뜬다. `aws-modules/rds/main.tf:62`가 `skip_final_snapshot = true`라 사고 비용이 크다.

## 2. 목표

- 컴포넌트별 state 분리
- 루트 간 의존성을 **1단**으로 평평하게
- 모듈을 재사용 단위로 분리

provider 분리(모든 루트가 `aws` 하나만 쓰게 하는 것)는 **이번 범위에 넣지 않는다.**
`aws-eks`는 ALB 컨트롤러의 `helm_release`를 그대로 가지므로 `kubernetes`·`helm` provider를
계속 쓴다. 분리는 §12의 개선 과제로 남긴다.

## 3. 확정된 결정

| # | 결정 | 근거 |
|---|---|---|
| 1 | 루트 5개 — `aws-core` `aws-eks` `aws-rds` `aws-cache` `aws-ops` | 5절 |
| 2 | 모듈 디렉터리를 `aws-modules/` · `gcp-modules/`로 분리 | 클라우드 간 공유 코드는 사실상 없다. 공유되는 것은 구조와 변수 규약이다 |
| 3 | DB·캐시 인바운드를 **EKS 클러스터 SG 참조 → 프라이빗 서브넷 CIDR 허용**으로 | 의존 사슬을 1단으로. 느슨해진 경계는 **NACL로 보완(보류)** |
| 4 | 루트 간 값 전달은 **`terraform_remote_state`** | 명시적이고, 기존 `data "aws_vpc"` 패턴과 공존한다 |
| 5 | 애플리케이션 매니페스트는 gitops 소유, 그 외 클러스터 구성요소는 현행 유지 | 이번 범위는 루트 분리다. 소유권 재배치는 함께 하지 않는다 |
| 6 | AWS Load Balancer Controller는 **Terraform이 설치 (현행 유지)** | 분리 이득은 있으나 이번 범위 밖. §12 개선 과제 |
| 7 | ALB 2개 — 서비스 ALB는 Ingress(컨트롤러 생성), ops ALB는 Terraform | 수명주기가 다르다. 7절 |
| 8 | IAM은 `eks-iam` 1모듈, `aws-eks` 루트 안 | 클러스터 ARN 을 문자열로 조립해 순환을 없앴다. §6 |
| 9 | ECR은 `aws-ops` 루트가 소유한다 **(2026-09-14 변경)** | 당초 "Infra 밖(CI/CD 소관)"이었으나 뒤집었다. 9절 |
| 10 | GCP는 이번 범위에서 제외 | 현재 `.tf` 0건, google provider 참조 0건 |

## 4. 디렉터리 구조

```
Infra/
├── aws-modules/                재사용 단위. backend 없음
│   ├── network/
│   ├── eks-iam/                IAM 역할·정책·부착 전부 (클러스터 미참조)
│   ├── eks/                    클러스터 · 노드그룹 · 애드온
│   ├── rds/
│   ├── elasticache/
│   ├── ecr/                            프라이빗 리포지터리 + 수명주기 정책
│   ├── aws-load-balancer-controller/   IAM · SA · helm_release (현행 그대로)
│   └── ops-alb/                        ops ALB. ALB 컨트롤러와 무관 [미구현]
├── gcp-modules/                (GCP 착수 시)
├── aws-core/                   루트
├── aws-eks/
├── aws-rds/
├── aws-cache/
├── aws-ops/
└── docs/specs/
```

루트 하나의 구성:

```
aws-eks/
├── backend.tf        전용 state key
├── versions.tf
├── providers.tf      aws 하나
├── main.tf
├── variables.tf
├── outputs.tf        다음 루트가 읽을 계약
└── terraform.tfvars  (.gitignore)
```

## 5. 루트별 내용과 의존 관계

| 루트 | 내용 | 읽는 것 | 노출하는 것 |
|---|---|---|---|
| `aws-core` | VPC(data 참조) · 서브넷 6 · IGW · NAT 2 · 라우팅 3 · S3 엔드포인트 연결 **[나중: NACL]** | — | `vpc_id` `vpc_cidr` `public_subnet_ids` `private_subnet_ids` `private_subnet_cidrs` `db_subnet_ids` |
| `aws-eks` | IAM 전체 · 클러스터 · 노드그룹 · 애드온 6 · Pod Identity 4개(`eks` 모듈 3 — karpenter·ebs_csi·bank_of_anthos + `aws-load-balancer-controller` 모듈 1) · access entry · **ALB 컨트롤러(helm) · k8s RBAC** | core | `cluster_name` `cluster_endpoint` `cluster_certificate_authority_data` `cluster_security_group_id` `node_group_name` |
| `aws-rds` | PostgreSQL · db-sg · 파라미터그룹 · 모니터링 IAM | core | `db_address` `db_port` `db_name` `master_user_secret_arn` `db_security_group_id` |
| `aws-cache` | Valkey Serverless · cache-sg · RBAC user/group · Secrets | core | `cache_endpoint` `secret_arn` `user_group_id` `cache_security_group_id` |
| `aws-ops` | **ECR 6개 + 수명주기 정책** · [미구현: ops ALB · 리스너 · 대상 그룹 · ops-alb-sg · Route53 · ECS] | **없음** (ECR만 있는 동안) | `ecr_registry` `ecr_repository_urls` `ecr_repository_names` `ecr_repository_arns` |

```
aws-core ──┬──→ aws-eks
           ├──→ aws-rds        서로 모른다. 동시 작업 가능
           ├──→ aws-cache
           └──→ aws-ops
```

`aws-rds`·`aws-cache`가 `aws-eks`를 보지 않는 이유가 결정 3이다. 현재 `modules/security/main.tf:130,164`의 인바운드가 `referenced_security_group_id = <EKS 클러스터 SG>`인데, 이를 `cidr_ipv4 = <프라이빗 서브넷 CIDR>`로 바꾼다.

`modules/security` 모듈은 **해체**한다. `db-sg`는 `aws-rds`로, `cache-sg`는 `aws-cache`로, `alb-sg`는 **삭제**한다 — 참조하는 곳이 없고(`module.security.alb_sg_id` 미사용), egress 블록이 없어 아웃바운드가 0인 상태다.

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

## 7. ALB 설계

### 두 ALB는 소유자가 다르다

| | 서비스 ALB | ops ALB |
|---|---|---|
| 만드는 주체 | ALB 컨트롤러 (Ingress 어노테이션) | Terraform (`aws-ops`) |
| 대상 | `frontend` | ArgoCD → 나중에 Grafana · Loki · Tempo |
| SG | 컨트롤러가 자동 생성·관리, 백엔드 SG 규칙도 자동 | Terraform이 만든 SG. **자동으로 안 열어준다** |
| 대상 등록 | 컨트롤러가 Ingress backend에서 자동 | `TargetGroupBinding`으로 명시 |
| 수명 | Ingress 삭제 시 함께 삭제 | Terraform이 지울 때까지 유지 |
| 호스트 | `app.bespinglobal.site` | `argocd.bespinglobal.site` |

수명주기가 다르기 때문에 관리 방식이 다르다. ArgoCD·Grafana는 클러스터를 재생성해도 접속 주소가 유지돼야 하고, DR 시 GCP 쪽을 가리키도록 바꿀 수도 있다.

**인증서는 공유한다.** `*.bespinglobal.site` 와일드카드가 이미 발급돼 있다(`arn:aws:acm:ap-northeast-2:769413326616:certificate/1c81ee2e-edbc-4a42-961d-816d571767ab`, 상태 ISSUED). Route53 퍼블릭 호스팅 영역 `bespinglobal.site.`(`Z03791674GY6T60MVQ4V`)도 같은 계정에 있다. ACM은 Terraform 관리 대상이 아니며 `data "aws_acm_certificate"`로 참조한다.

### ops ALB 연결 시 맞춰야 할 네 가지

1. **`TargetGroupBinding`에 `spec.networking`이 필요하다.** 현재 `gitops/scripts/bootstrap-eks.sh:585`가 렌더링하는 매니페스트에 이 블록이 없다. SG를 직접 지정한 ALB는 컨트롤러가 백엔드 SG 규칙을 자동으로 열지 않으므로, `networking.ingress[].from[].securityGroup.groupID`에 ops-alb-sg를 명시해야 한다. → `aws-ops`가 `alb_security_group_id`를 output으로 내고 `aws.env`에 주입한다.

2. **`argocd-server`를 `insecure`로 띄워야 한다.** `gitops/bootstrap/argocd/values.yaml`에 설정이 없다. 기본값은 자체 서명 TLS + HTTP→HTTPS 리다이렉트라, ALB에서 TLS를 끊으면 리다이렉트 루프가 된다.

3. **CRD가 먼저 있어야 한다.** `TargetGroupBinding`은 ALB 컨트롤러가 설치하는 CRD다. 컨트롤러를 Terraform이 설치하므로 `aws-eks` apply 시점에 CRD가 생기고, kubectl 단계는 그 뒤다 — 순서가 자연히 맞는다. `bootstrap-eks.sh:787`의 CRD 확인도 그대로 통과한다.

4. **헬스체크를 명시한다.** 포트 8080, 경로 `/healthz`, 프로토콜 HTTP(1의 insecure 적용 후).

### 삭제 순서 주의

Ingress가 만든 ALB는 Terraform state에 없다. ALB의 ENI가 퍼블릭 서브넷에 꽂혀 있으므로, Ingress를 지우지 않고 `aws-core`를 destroy하면 서브넷 삭제가 `DependencyViolation`으로 막힌다.

```
1. kubectl delete ingress (또는 ArgoCD Application 삭제)
2. ALB·SG 소멸 확인
3. terraform destroy
```

## 8. 클러스터 소유권

이번 범위에서 gitops로 넘기는 것은 **애플리케이션 매니페스트뿐**이다.

| 대상 | 현재 위치 | 이번 범위 |
|---|---|---|
| 애플리케이션 매니페스트 25개 | `Infra/boa/k8s/` | **gitops 저장소로 이관** |
| ALB 컨트롤러 `helm_release` · `ServiceAccount` | `modules/aws-load-balancer-controller/main.tf:38,53` | `aws-eks` 루트에 그대로 |
| `kubernetes_cluster_role_v1` · `_binding_v1` | `modules/eks/iam.tf:434,461` | `aws-eks` 루트에 그대로 |

따라서 `aws-eks`는 `aws` · `kubernetes` · `helm` 세 provider를 쓴다. 그 결과로,

- 클러스터가 없거나 API에 닿지 않으면 이 루트는 `plan`이 실패한다 — 변경 대상이 순수 AWS 리소스여도 마찬가지다. `main.tf`의 `public_access_cidrs`가 코드 서버 IP를 고정하고 있어, 인스턴스 재기동으로 IP가 바뀌면 이 상황이 실제로 발생한다.
- `destroy` 시 `helm_release`가 먼저 파괴되어 컨트롤러가 사라진다. **Ingress를 먼저 지우지 않으면 ALB를 정리할 주체가 없어져 고아가 된다.**

두 번째는 절차로 막는다 — §7의 삭제 순서를 지키면 정상 동작한다. 구조적 해소는 §12의 개선 과제다.

**초기 배포는 ArgoCD가 아니다.** `aws-eks` apply가 끝난 뒤 코드 서버에서 kubectl로 매니페스트를 적용한다. ArgoCD는 그 이후 단계다.

## 9. ECR

**2026-09-14 결정을 뒤집었다.** 당초 "ECR은 Infra 밖(CI/CD 소관)"이었으나, `aws-ops` 루트가
소유하는 것으로 바꿨다. `gitops/scripts/bootstrap-eks.sh:233`이 `terraform output -json`에서
`ecr_registry`를 읽고 245–262행의 **필수 목록**에 두고 있어서, Infra가 그 값을 내주는 쪽이
부트스트랩이 그대로 통과한다.

`aws-ops`의 `ecr_registry` output은 **호스트만** 낸다. 스크립트 291행이 정규식으로 검사한다.

    ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com$

리포지터리 경로가 붙으면 여기서 떨어진다.

### 이름은 `boa-` 접두사를 붙인다

    boa-frontend  boa-userservice  boa-contacts
    boa-balancereader  boa-ledgerwriter  boa-transactionhistory

접두사 없는 기존 6개(`frontend` `userservice` …)는 **손으로 만든 것이고 이미 이미지가 들어
있다**(frontend 11개, userservice 8개, balancereader 9개 — 2026-09-14 확인). 이 스택은 그것을
소유하지 않으며, 같은 이름으로 만들면 `RepositoryAlreadyExistsException`이 난다.

**따라오는 작업 — gitops 저장소**

`k8s/overlays/dev/aws/kustomization.yaml:27–42`의 `newName` 6줄이 접두사 없는 이름을 박고 있다.
새 리포지터리를 쓰려면 그 6줄을 `boa-` 접두사로 바꾸고, **CI가 새 리포지터리로 이미지를 다시
푸시**해야 한다. 레지스트리 호스트는 계정·리전 조합이라 바뀌지 않는다.

기존 6개를 언제 정리할지는 미정이다 — 새 리포지터리로 전환이 끝나고 롤백이 필요 없어진 뒤다.

### 설정

| 항목 | 값 | 이유 |
|---|---|---|
| 태그 변경 | `IMMUTABLE` | 같은 태그 재푸시 차단. CI가 커밋 SHA로 태깅하는 전제 |
| 푸시 시 스캔 | 켬 | ECR 기본 스캔은 무료다. 기존 6개는 꺼져 있었다 |
| 암호화 | `AES256` | |
| 수명주기 | untagged 1일 후 만료 → 최신 10개 유지 | `tagStatus = "any"` 규칙은 `rulePriority`가 가장 커야 해서 마지막에 둔다 |
| `force_delete` | `false` | 이미지가 남아 있으면 destroy가 막힌다. 실수 방지 |

## 10. state 배치

```
s3://boa-terraform-state-6416/
├── aws/core/terraform.tfstate
├── aws/eks/terraform.tfstate
├── aws/rds/terraform.tfstate
├── aws/cache/terraform.tfstate
└── aws/ops/terraform.tfstate
```

버킷은 `ap-northeast-2`, 버전 관리 Enabled, AES256, 퍼블릭 4종 차단. `use_lockfile = true`(S3 네이티브 락)이므로 락 객체가 `<key>.tflock`으로 key마다 따로 생긴다. DynamoDB 테이블은 불필요하다(`dynamodb_table`은 deprecated).

## 11. 이행 순서

1. `git mv`로 `modules/*` → `aws-modules/*` (이력 보존)
2. `modules/security` 해체 — db-sg·cache-sg 이관, alb-sg 삭제
3. `aws-modules/eks`에서 IAM을 `eks-iam` 1모듈로 분리
4. `modules/aws-load-balancer-controller`는 **그대로 옮기기만 한다** — `aws-modules/aws-load-balancer-controller`. 내용 변경 없음
5. 루트 5개 생성 (`backend.tf` · `providers.tf` · `main.tf` · `variables.tf` · `outputs.tf`)
6. 기존 루트 `main.tf` · `backend.tf` · `provider.tf` 제거
7. `Infra/boa/k8s/` → gitops 저장소 이관
8. 루트별 `terraform init -backend=false` + `validate`

**아직 apply한 적이 없어 state 마이그레이션이 필요 없다.** 구조를 바꾸기에 가장 저렴한 시점이다. apply 이후였다면 루트별 `terraform state mv`가 필요했다.

## 12. 미정 사항

| 항목 | 내용 | 결정 시한 |
|---|---|---|
| **ALB 컨트롤러 분리** | `helm_release`·`ServiceAccount`·k8s RBAC를 `aws-eks`에서 빼면 이 루트가 `aws` provider 하나가 되어 클러스터 상태와 무관하게 `plan`이 돈다. 빼는 방식은 코드 서버의 helm 명령(권장) 또는 렌더한 매니페스트. 같이 고칠 것 — 차트 버전 고정(현재 `version` 인자 없음), `serviceAccount.create=true`로 전환(현재 `automount_service_account_token = false`) | 루트 분리 완료 후 |
| NACL 설계 | 결정 3의 보완책. 서브넷 경계 규칙 | 루트 분리 완료 후, 운영 전환 전 |
| 매니페스트 배포 주체 | 초기 매니페스트를 Terraform이 배포할지 재검토 | 별도 검토 (이번 범위 밖) |
| Grafana 배치 | EKS 파드 / ECS 태스크 / 프라이빗 서브넷 EC2 | `observability` 착수 전 |
| `observability` 루트 범위 | CloudWatch / ADOT / Prometheus·Grafana·Loki·Tempo 조합 | 별도 브리핑 필요 |
| ECR 파급 처리 | 9절 (a)(b)(c) 중 선택 | gitops 부트스트랩 실행 전 |
| GCP state 백엔드 | GCS 버킷·경로. S3에 두면 GCP가 AWS 자격증명을 갖게 된다 | GCP 착수 전 |
| dev/prod 환경 분리 | 현재 단일 | 운영 전환 전 |

**절대 날짜는 팀 일정이 정해진 뒤 채운다.**

## 13. 확인이 필요한 기존 문제

루트 분리와 별개로, 현재 코드에 남아 있는 문제들이다.

| 문제 | 위치 | 비고 |
|---|---|---|
| 노드 역할이 Secrets Manager `/boa/*`에 직접 접근 | `aws-modules/eks-iam/main.tf:320-325` | 그 노드의 모든 파드가 IMDS로 접근 가능. Pod Identity를 쓰는 취지를 깨뜨린다. **단, Secrets Store CSI 드라이버가 이 경로를 쓰고 있을 수 있어 제거 전 확인 필요** |
| Pod Identity 네임스페이스가 `default` | `aws-modules/eks/iam.tf:27` | 라이브 앱 네임스페이스는 `bank-of-anthos`. 다르면 파드가 자격증명을 못 받는다 |
| ALB 컨트롤러 SA의 `automount_service_account_token = false` | `aws-modules/aws-load-balancer-controller/main.tf:43` | 컨트롤러는 kube API 토큰이 필요하다. Helm 차트가 파드 레벨에서 켜주는지 확인 필요 |
| EKS 퍼블릭 엔드포인트에 코드 서버 IP 하드코딩 | `aws-eks/main.tf:29` (`15.165.176.99/32`) | 인스턴스 재기동 시 변경된다. 변수화 필요 |
| 루트 `outputs.tf`가 gitops 요구와 다름 | 각 루트 `outputs.tf` | 네 루트 모두 `outputs.tf`는 있다. 다만 gitops 부트스트랩이 요구하는 output 9종(`aws_region` `aws_account_id` `ecr_registry` `eks_cluster_name` `rds_address` `rds_port` `rds_master_user_secret_arn` `rds_app_secret_arn` `rds_bootstrap_db_name`)과 이름·구성이 다르다 — 예: `aws-rds`는 `db_address`·`db_port`를 내지만 `rds_address`·`rds_port`가 아니고, `aws_region`·`aws_account_id`·`ecr_registry`·`rds_app_secret_arn`·`rds_bootstrap_db_name`은 어느 루트에도 없다 |

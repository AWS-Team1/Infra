# Terraform 루트 분리 설계

- 작성일: 2026-09-14 (최종 갱신 2026-09-14)
- 대상 저장소: `AWS-TEAM1-DEV/Infra` (2026-09-14 조직 이관. 이전 `swoobuntu/Infra`)
- 작업 브랜치: `dev` (이전 `Karfa-choi`. `dev` · `release` · `Karfa-choi` 모두 같은 지점)
- 선행 커밋: `97a01b6` (boa- 접두사 전환, 기존 VPC 재사용)
- **구현 상태: 루트 분리·태그·ECR·ops ALB·주석·DNS 제거까지 반영 완료.** 루트 5개 `validate` 통과.
  `terraform apply`·`plan`은 아직 한 번도 실행하지 않았고 state 버킷은 비어 있다.
  남은 것은 §11의 7번(`boa/k8s` 이관)과 14번(코드 서버 remote)이다.

**2026-09-14 계정 현황 확인.** EKS 클러스터 0개, RDS 0개, ElastiCache 0개, ALB 0개,
`boa-` IAM 역할 0개, state 버킷 비어 있음. 대상 VPC에 IGW 없음(코드가 새로 만든다),
기존 서브넷은 `192.168.0.0/24` · `192.168.1.0/24`뿐이라 신규 6개와 겹치지 않는다.
**충돌 지점은 Route53 고아 CNAME 하나뿐이었고, 결정 11로 해소했다.**
남아 있는 기존 자원은 접두사 없는 ECR 6개(이미지 포함)와 그 CNAME이다.

이 문서는 **설계와 현재 코드를 함께** 기술한다. 이미 구현된 항목은 현재형으로,
검토 끝에 폐기한 안은 "폐기"로 명시해 남긴다.

## 1. 배경

분리 전 `Infra/`는 **단일 루트 모듈**이었다. 루트 `main.tf`가 모듈 6종을 호출하고 state 하나가 전부를 담았다.

문제는 셋이다.

1. **작업이 직렬화된다.** 누가 apply하면 state 락이 전체를 잠근다. RDS apply는 십수 분 걸린다.
2. **provider가 섞여 있다.** `provider.tf`의 kubernetes·helm이 `module.eks` 출력에 의존해, 클러스터가 없으면 `plan`조차 돌지 않는다.
3. **폭발 반경이 하나다.** 서브넷 하나 고치는 plan에 RDS 변경이 같이 뜬다. `aws-modules/rds/main.tf:68`이 `skip_final_snapshot = true`라 사고 비용이 크다.

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
| 8 | IAM은 `eks-iam` **1모듈**, `aws-eks` 루트 안 | 클러스터 ARN 을 문자열로 조립해 순환을 없앴다. 초안의 `eks-iam-base`/`eks-iam-workload` **2분할안은 폐기**했다. §6 |
| 9 | ECR은 `aws-ops` 루트가 소유한다 **(2026-09-14 변경)** | 당초 "Infra 밖(CI/CD 소관)"이었으나 뒤집었다. 9절 |
| 10 | GCP는 이번 범위에서 제외 | 현재 `.tf` 0건, google provider 참조 0건 |
| 11 | **DNS 레코드는 Terraform이 만들지 않는다 (2026-09-14 추가)** | 호스팅 영역이 공용이고, 대상 이름에 고아 CNAME이 이미 있어 충돌한다. 원래 이 저장소에 route53 코드는 없었다. §7 |

## 4. 디렉터리 구조

아래는 **현재 저장소의 실제 구조**다.

```
Infra/
├── aws-modules/                재사용 단위. backend 없음
│   ├── network/                VPC(data 참조) · 서브넷 · IGW · NAT · 라우팅
│   ├── eks-iam/                IAM 역할·정책·부착 전부 (클러스터 미참조)
│   ├── eks/                    클러스터 · 노드그룹 · 애드온 · Pod Identity · access entry
│   │                           main.tf addons.tf iam.tf access.tf secrets.tf
│   ├── rds/                    main.tf iam.tf security.tf
│   ├── elasticache/            main.tf security.tf
│   ├── ecr/                            프라이빗 리포지터리 + 수명주기 정책
│   ├── ops-alb/                        ops ALB. ALB 컨트롤러와 무관
│   └── aws-load-balancer-controller/   IAM · SA · helm_release (현행 그대로)
│                                       + iam-policy.json
├── aws-core/                   루트 5개
├── aws-eks/
├── aws-rds/
├── aws-cache/
├── aws-ops/
├── boa/k8s/                    매니페스트 25개 — gitops 이관 대기 (§11-7)
└── docs/
    ├── specs/                  이 문서
    └── plans/                  이행 계획
```

`gcp-modules/`는 **아직 없다.** GCP 착수 시 만든다(결정 10).

루트 하나의 구성:

```
aws-eks/
├── backend.tf        전용 state key
├── versions.tf
├── providers.tf      aws · kubernetes · helm  (다른 넷은 aws 하나)
├── main.tf           terraform_remote_state "core" 포함
├── variables.tf      aws-eks 에만 있다 (code_server_role_arn)
├── rbac.tf           aws-eks 에만 있다 (k8s ClusterRole/Binding)
├── outputs.tf        다음 루트가 읽을 계약
└── terraform.tfvars  (.gitignore — 저장소에 없다)
```

## 5. 루트별 내용과 의존 관계

| 루트 | 내용 | 읽는 것 | 노출하는 것 |
|---|---|---|---|
| `aws-core` | VPC(data 참조) · 서브넷 **8**(public 2 · private 2 · db 2 · cache 2) · IGW · NAT 2 · 라우팅 3 · S3 엔드포인트 연결 **[나중: NACL]** | — | `vpc_id` `vpc_cidr` `igw_id` `public_subnet_ids` `private_subnet_ids` `private_subnet_cidrs` `db_subnet_ids` `cache_subnet_ids` |
| `aws-eks` | IAM 전체 · 클러스터 · 노드그룹 · 애드온 6 · Pod Identity 4개(`eks` 모듈 3 — karpenter·ebs_csi·bank_of_anthos + `aws-load-balancer-controller` 모듈 1) · access entry · **ALB 컨트롤러(helm) · k8s RBAC** | core | `cluster_name` `cluster_endpoint` `cluster_certificate_authority_data` `cluster_security_group_id` `node_group_name` |
| `aws-rds` | PostgreSQL · db-sg · 파라미터그룹 · 모니터링 IAM | core | `db_address` `db_port` `db_name` `master_user_secret_arn` `db_security_group_id` |
| `aws-cache` | Valkey Serverless · cache-sg · RBAC user/group · Secrets | core | `cache_endpoint` `secret_arn` `user_group_id` `cache_security_group_id` |
| `aws-ops` | ECR 6개 + 수명주기 · **ops ALB · 리스너 2 · 대상 그룹 · ops-alb-sg** · [미구현: ECS] · <s>Route53</s> **DNS는 관리하지 않는다(§7)** | core | `ecr_registry` `ecr_repository_urls` `ecr_repository_names` `ecr_repository_arns` `ops_alb_dns_name` `ops_alb_zone_id` `ops_alb_security_group_id` `argocd_target_group_arn` `argocd_url` `ops_alb_https_listener_arn` |

```
aws-core ──┬──→ aws-eks
           ├──→ aws-rds        서로 모른다. 동시 작업 가능
           ├──→ aws-cache
           └──→ aws-ops
```

`aws-rds`·`aws-cache`가 `aws-eks`를 보지 않는 이유가 결정 3이다. 분리 전 `modules/security/main.tf:130,164`의 인바운드는 `referenced_security_group_id = <EKS 클러스터 SG>`였고, 이를 `cidr_ipv4 = <프라이빗 서브넷 CIDR>`로 바꿨다.

**완료.** `modules/security` 모듈은 해체했다. `db-sg`는 `aws-modules/rds/security.tf`로, `cache-sg`는 `aws-modules/elasticache/security.tf`로 옮겼고, `alb-sg`는 삭제했다 — 참조하는 곳이 없었고(`module.security.alb_sg_id` 미사용), egress 블록이 없어 아웃바운드가 0인 상태였다.

ops ALB의 SG는 이것과 **별개로 새로 만든 것**이다(`aws-modules/ops-alb`). 삭제한 `alb-sg`의 부활이 아니며, egress를 명시해 아웃바운드 0 문제를 반복하지 않는다 — `aws_security_group`은 egress 블록이 없으면 AWS 기본 전체 허용 규칙이 제거된다.

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

### 폐기한 안 — `eks-iam-base` / `eks-iam-workload` 분할

이 문서의 **초안은 IAM을 `eks-iam-base` · `eks` · `eks-iam-workload` 3모듈로 나눴다.**
구현 착수 전에 폐기했으므로 현재 디렉터리에는 존재하지 않는다. 폐기 이유는 둘이다.

1. **3모듈로도 순환이 남는다.** `aws-modules/eks/addons.tf`의 EBS CSI 애드온이
   `aws_eks_pod_identity_association.ebs_csi`에 `depends_on`을 건다. 이 연결이 workload
   모듈 소관이면 workload → eks 의존이 생겨 `eks ↔ workload` 순환이 된다.
2. **분할을 유지하려면 짝을 갈라야 한다.** Karpenter의 역할(base)과 정책(workload)을 서로
   다른 모듈에 두게 되는데, 같은 짝을 두 모듈에 나누는 편이 순환보다 나쁘다.

위의 문자열 조립으로 순환의 원인 자체가 사라지므로 분할의 근거도 함께 사라졌다.
경위는 `docs/plans/2026-09-14-terraform-root-split.md`의 "설계 문서와 다른 점" 절에 있다.

**현재 배치는 이렇다.**

| 위치 | 내용 |
|---|---|
| `aws-modules/eks-iam/main.tf` | `aws_iam_*` 18개. 클러스터 미참조 |
| `aws-modules/eks/iam.tf` | `aws_eks_pod_identity_association` 3개 — karpenter · ebs_csi · bank_of_anthos |

`eks/iam.tf`에 남은 셋은 IAM 리소스가 아니라 **EKS 리소스**다. 파일 이름 때문에 IAM으로
보이지만, `eks` 모듈 안에 있어야 `aws_eks_addon.ebs_csi`의 `depends_on`이 같은 모듈에서 풀린다.

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
| DNS 레코드 | 컨트롤러도 Terraform도 안 만든다 | **Terraform이 안 만든다 (아래)** |

수명주기가 다르기 때문에 관리 방식이 다르다. ArgoCD·Grafana는 클러스터를 재생성해도 접속 주소가 유지돼야 하고, DR 시 GCP 쪽을 가리키도록 바꿀 수도 있다.

**인증서는 공유한다.** `*.bespinglobal.site` 와일드카드가 이미 발급돼 있다(`arn:aws:acm:ap-northeast-2:769413326616:certificate/1c81ee2e-edbc-4a42-961d-816d571767ab`, 상태 ISSUED). ACM은 Terraform 관리 대상이 아니며 `data "aws_acm_certificate"`로 참조한다.

**와일드카드는 한 단계만 덮는다.** `boa-argocd.bespinglobal.site`는 덮이지만 `argocd.boa.bespinglobal.site`는 덮이지 않는다. 호스트명을 바꿀 때 점을 하나 더 넣으면 HTTPS에서 인증서 오류가 난다.

### DNS는 Terraform이 관리하지 않는다 (2026-09-14 결정)

ops ALB 모듈은 처음에 `aws_route53_record.argocd`로 A(alias) 레코드를 만들었다. **뺐다.**

퍼블릭 호스팅 영역 `bespinglobal.site.`(`Z03791674GY6T60MVQ4V`)는 이 계정에 있지만 **공용이다.** 조회 결과 `app` · `prod` · `origin` · 루트 A · ACM 검증용 CNAME이 함께 들어 있다. 이 스택이 소유한 영역이 아니다.

거기에 `argocd.bespinglobal.site`에 **이미 CNAME이 있다** — 이미 삭제된 ALB(`k8s-argocd-argocdse-867c2af99f-...`)를 가리키는 고아 레코드다(2026-09-14 확인, 계정에 ALB 0개). DNS 규칙상 **CNAME은 같은 이름의 다른 타입과 공존할 수 없어** A(alias) 생성이 충돌한다.

애초에 **이 저장소에 route53 코드는 없었다.** ops ALB를 만들며 새로 들어온 것이라 원래 범위로 되돌렸다.

그 결과 `aws-ops`가 내는 것은 ALB까지이고, 레코드는 밖에서 잡는다.

    ops_alb_dns_name   A(alias) 의 대상 이름
    ops_alb_zone_id    A(alias) 의 대상 영역 ID

`var.argocd_host`는 남긴다. **리스너 규칙의 `host_header` 조건에 쓰이기 때문**이다. 이 이름으로 오지 않은 요청은 443 기본 동작인 404로 떨어진다. 따라서 밖에서 잡는 레코드의 이름이 `argocd_host`와 **같아야 한다.**

고아 CNAME 처리는 미정이다 — 남의 레코드가 섞인 영역이라 팀 확인이 필요하다. 선택지는 (a) 기존 CNAME의 값을 새 ALB DNS 이름으로 수정(타입이 그대로라 충돌 없음), (b) 고아 삭제 후 A(alias) 신규 생성, (c) `boa-argocd` 등 다른 호스트명 사용.

### ops ALB 연결 시 맞춰야 할 네 가지

1. **`TargetGroupBinding`에 `spec.networking`이 필요하다.** `gitops/scripts/bootstrap-eks.sh:585-601`이 렌더링하는 매니페스트에 이 블록이 없다(`targetGroupARN` · `targetType` · `serviceRef`만 있다 — 2026-09-14 확인). SG를 직접 지정한 ALB는 컨트롤러가 백엔드 SG 규칙을 자동으로 열지 않으므로, `networking.ingress[].from[].securityGroup.groupID`에 ops-alb-sg를 명시해야 한다. → `aws-ops`가 **`ops_alb_security_group_id`**를 output으로 내므로, 이 값을 `aws.env`의 새 변수로 주입한다(현재 `aws.env`에 해당 변수가 없다).

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
| 애플리케이션 매니페스트 25개 | `Infra/boa/k8s/` | **gitops 저장소로 이관 — 아직 미완(§11-7)** |
| ALB 컨트롤러 `helm_release` · `ServiceAccount` | `aws-modules/aws-load-balancer-controller/main.tf:50,69` | `aws-eks` 루트에 그대로 |
| `kubernetes_cluster_role_v1` · `_binding_v1` | `aws-eks/rbac.tf:4,32` | 루트 분리 시 `aws-modules/eks/iam.tf`에서 **루트로 꺼냈다.** 모듈이 `aws` provider 하나만 쓰게 하기 위해서다 |

따라서 `aws-eks`는 `aws` · `kubernetes` · `helm` 세 provider를 쓴다. 그 결과로,

- 클러스터가 없거나 API에 닿지 않으면 이 루트는 `plan`이 실패한다 — 변경 대상이 순수 AWS 리소스여도 마찬가지다. `main.tf`의 `public_access_cidrs`가 코드 서버 IP를 고정하고 있어, 인스턴스 재기동으로 IP가 바뀌면 이 상황이 실제로 발생한다.
- `destroy` 시 `helm_release`가 먼저 파괴되어 컨트롤러가 사라진다. **Ingress를 먼저 지우지 않으면 ALB를 정리할 주체가 없어져 고아가 된다.**

두 번째는 절차로 막는다 — §7의 삭제 순서를 지키면 정상 동작한다. 구조적 해소는 §12의 개선 과제다.

**초기 배포는 ArgoCD가 아니다.** `aws-eks` apply가 끝난 뒤 코드 서버에서 kubectl로 매니페스트를 적용한다. ArgoCD는 그 이후 단계다.

## 9. ECR

**2026-09-14 결정을 뒤집었다.** 당초 "ECR은 Infra 밖(CI/CD 소관)"이었으나, `aws-ops` 루트가
소유하는 것으로 바꿨다. `gitops/scripts/bootstrap-eks.sh:235`가 `terraform output -json`에서
`ecr_registry`를 읽고 246–254행의 **필수 목록**에 두고 있어서, Infra가 그 값을 내주는 쪽이
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

| # | 단계 | 상태 |
|---|---|---|
| 1 | `git mv`로 `modules/*` → `aws-modules/*` (이력 보존) | 완료 |
| 2 | `modules/security` 해체 — db-sg·cache-sg 이관, alb-sg 삭제 | 완료 |
| 3 | `aws-modules/eks`에서 IAM을 `eks-iam` 1모듈로 분리 | 완료 |
| 4 | `aws-load-balancer-controller`는 **그대로 옮기기만** (내용 변경 없음) | 완료 |
| 5 | 루트 5개 생성 (`backend.tf` · `providers.tf` · `main.tf` · `outputs.tf`) | 완료 |
| 6 | 기존 루트 `main.tf` · `backend.tf` · `provider.tf` 제거 | 완료 |
| 7 | `Infra/boa/k8s/` → gitops 저장소 이관 | **미완** |
| 8 | 루트별 `terraform init -backend=false` + `validate` | 완료 |

루트 분리 이후 같은 브랜치에서 이어서 한 것:

| 단계 | 내용 | 상태 |
|---|---|---|
| 9 | 리소스 태그 보강 — `Name` 누락분 + 루트별 `default_tags` | 완료 |
| 10 | `aws-modules/ecr` 신설, `aws-ops`가 호출 (§9) | 완료 |
| 11 | `aws-modules/ops-alb` 신설, `aws-ops`가 호출 (§7) | 완료 |
| 12 | 전 리소스 선언 위에 역할·연결 주석 부착 | 완료 |
| 13 | ops ALB에서 Route53 레코드 제거, `ops_alb_zone_id` output 추가 (§7) | 완료 |
| 14 | 저장소 조직 이관에 따른 remote 주소 변경 | 로컬 5개 완료 · **코드 서버 미완** |
| 15 | 5개 루트 `default_tags`의 `Repo`를 `AWS-TEAM1-DEV/Infra`로 | 완료 |
| 16 | ElastiCache 전용 서브넷 분리 (§12.1) | 코드 완료 · **`aws-core` 재apply 필요** |

**아직 apply한 적이 없어 state 마이그레이션이 필요 없었다.** 구조를 바꾸기에 가장 저렴한 시점이었다. apply 이후였다면 루트별 `terraform state mv`가 필요했다.

검증은 `terraform fmt -recursive -check` + 루트별 `init -backend=false` + `validate`까지다.
**`plan`·`apply`는 이 작업 범위 밖이었고 실행하지 않았다** — 로컬에 AWS 자격증명이 없고,
실행은 코드 서버에서 한다.

## 12. 미정 사항

| 항목 | 내용 | 결정 시한 |
|---|---|---|
| **ALB 컨트롤러 분리** | `helm_release`·`ServiceAccount`·k8s RBAC를 `aws-eks`에서 빼면 이 루트가 `aws` provider 하나가 되어 클러스터 상태와 무관하게 `plan`이 돈다. 빼는 방식은 코드 서버의 helm 명령(권장) 또는 렌더한 매니페스트. 같이 고칠 것 — 차트 버전 고정(현재 `version` 인자 없음), `serviceAccount.create=true`로 전환(현재 `automount_service_account_token = false`) | **루트 분리는 끝났다. 착수 가능** |
| NACL 설계 | 결정 3의 보완책. 서브넷 경계 규칙. 캐시 서브넷 분리(§12.1)가 선행 조건이었고 **해소됐다** | **루트 분리는 끝났다.** 운영 전환 전 |
| `boa/k8s` 25개 이관 | §11-7 | gitops 부트스트랩 실행 전 |
| **ArgoCD DNS 레코드 주체** | Terraform이 안 만든다(결정 11). 고아 CNAME 수정 / 삭제 후 A(alias) / 다른 호스트명 중 택1. 영역이 공용이라 팀 확인 필요 | `aws-ops` apply 후, ArgoCD 노출 전 |
| 브랜치와 state의 관계 | `backend.tf` key가 브랜치와 무관하다. `dev`·`release`에서 각각 apply하면 같은 state를 번갈아 덮어쓴다. 현재는 **`dev` 한 곳에서만 apply** | dev/prod 분리 결정 시 |
| **output 계약 맞추기** | 루트가 5개로 갈라져 gitops가 요구하는 output 9종이 세 루트에 흩어졌다. 집계 루트 / 스크립트 수정 / `aws.env` 직접 기입 중 택1. §13.1 | gitops 부트스트랩 실행 전 |
| `rds_app_secret_arn` 신설 | 애플리케이션 전용 DB 시크릿. master와 같으면 부트스트랩이 거부한다 | 위와 동시 |
| 매니페스트 배포 주체 | 초기 매니페스트를 Terraform이 배포할지 재검토 | 별도 검토 (이번 범위 밖) |
| Grafana 배치 | EKS 파드 / ECS 태스크 / 프라이빗 서브넷 EC2 | `observability` 착수 전 |
| `observability` 루트 범위 | CloudWatch / ADOT / Prometheus·Grafana·Loki·Tempo 조합 | 별도 브리핑 필요 |
| 기존 ECR 6개 정리 시점 | 접두사 없는 손수 만든 리포지터리. `boa-` 전환이 끝나고 롤백이 불필요해진 뒤 (§9) | 전환 완료 후 |
| GCP state 백엔드 | GCS 버킷·경로. S3에 두면 GCP가 AWS 자격증명을 갖게 된다 | GCP 착수 전 |
| dev/prod 환경 분리 | 현재 단일 | 운영 전환 전 |

**절대 날짜는 팀 일정이 정해진 뒤 채운다.**

### 12.1 ElastiCache 전용 서브넷 (2026-09-14 구현 완료)

**분리 전** 배치는 이랬다 — DB는 분리했는데 캐시만 프라이빗에 얹혀 있었다.

    192.168.8.0/24   boa-private-a   EKS 노드·파드 + ElastiCache   ← 공유
    192.168.9.0/24   boa-private-c   EKS 노드·파드 + ElastiCache   ← 공유
    192.168.16.0/24  boa-db-a        RDS 전용
    192.168.17.0/24  boa-db-c        RDS 전용

**분리 후**는 이렇다.

    192.168.8.0/24   boa-private-a   EKS 노드·파드
    192.168.9.0/24   boa-private-c   EKS 노드·파드
    192.168.16.0/24  boa-db-a        RDS 전용
    192.168.17.0/24  boa-db-c        RDS 전용
    192.168.24.0/24  boa-cache-a     ElastiCache 전용
    192.168.25.0/24  boa-cache-c     ElastiCache 전용

분리한 이유는 둘이다.

1. **IP 고갈.** VPC CNI라 파드 하나가 프라이빗 서브넷 IP를 하나씩 쓴다. `/24`는 가용 251개이고 노드 ENI와 ElastiCache ENI가 더 붙는다. Karpenter가 노드를 늘리면 더 빨리 준다.
2. **NACL이 무력해진다.** NACL은 서브넷 단위다. 캐시와 파드가 같은 서브넷이면 그 경계로 둘을 구분할 수 없다. §12의 NACL 과제가 이것 때문에 반쪽이 된다.

보안 그룹은 영향이 없다. 인바운드를 프라이빗 CIDR로 여는 것은 **클라이언트가 있는 곳** 기준이라 캐시를 어디 두든 그대로다. 그래서 `aws-cache`는 `private_subnet_cidrs`(SG용)와 `cache_subnet_ids`(배치용)를 **따로** 받는다.

캐시는 아웃바운드 인터넷이 필요 없으므로 db 서브넷처럼 **라우팅 테이블을 붙이지 않고** 메인 RT(local만)를 상속시킨다.

검토했다가 택하지 않은 안 — **db 서브넷 재사용.** 한 줄로 끝나지만 `boa-db-*`라는 이름에 캐시가 들어가고, RDS와 캐시가 같은 NACL 경계를 공유하게 되어 1번 문제만 풀고 2번은 절반만 푼다.

**시점.** `aws-cache` apply **전에** 반영했다. 서브넷 그룹은 생성 후 변경이 제한적이라, 이미 apply한 ElastiCache의 `subnet_ids`를 바꾸면 **교체(force new)**가 걸린다. 먼저 올렸다면 캐시를 한 번 버려야 했다.

`aws-core`는 이미 apply된 상태(2026-09-14 17:30)이므로 **서브넷 2개 추가로 재apply가 필요하다.** 기존 리소스는 건드리지 않는다 — `Plan: 2 to add, 0 to change, 0 to destroy`가 나와야 한다.

건드린 곳은 다섯이다.

| 파일 | 내용 |
|---|---|
| `aws-modules/network/main.tf` | `aws_subnet.cache_a` · `cache_c` |
| `aws-modules/network/variables.tf` | `var.cache_subnet_cidrs` |
| `aws-modules/network/outputs.tf` | `cache_subnet_ids` |
| `aws-core/main.tf` | CIDR `192.168.24.0/24` · `192.168.25.0/24` |
| `aws-core/outputs.tf` | `cache_subnet_ids` 노출 |
| `aws-cache/main.tf` | `private_subnet_ids` → `cache_subnet_ids` |

## 13. 확인이 필요한 기존 문제

루트 분리와 별개로, 현재 코드에 남아 있는 문제들이다.

| 문제 | 위치 | 비고 |
|---|---|---|
| 노드 역할이 Secrets Manager `/boa/*`에 직접 접근 | `aws-modules/eks-iam/main.tf:331` (`aws_iam_policy.node_secrets`) | 그 노드의 모든 파드가 IMDS로 접근 가능. Pod Identity를 쓰는 취지를 깨뜨린다. **단, Secrets Store CSI 드라이버가 이 경로를 쓰고 있을 수 있어 제거 전 확인 필요** |
| Pod Identity 네임스페이스가 `default` | `aws-modules/eks/iam.tf:33` | 라이브 앱 네임스페이스는 `bank-of-anthos`. 다르면 파드가 자격증명을 못 받는다 |
| ALB 컨트롤러 SA의 `automount_service_account_token = false` | `aws-modules/aws-load-balancer-controller/main.tf:55` | 컨트롤러는 kube API 토큰이 필요하다. Helm 차트가 파드 레벨에서 켜주는지 확인 필요 |
| ALB 컨트롤러 helm 차트 버전 미고정 | `aws-modules/aws-load-balancer-controller/main.tf:69` (`version` 인자 없음) | 최신 차트를 매번 끌어온다. apply 시점에 따라 결과가 달라진다 |
| EKS 퍼블릭 엔드포인트에 코드 서버 IP 하드코딩 | `aws-eks/main.tf:29` (`15.165.176.99/32`) | 인스턴스 재기동 시 변경된다. 변수화 필요 |
| 루트 `outputs.tf`가 gitops 요구와 다름 | 각 루트 `outputs.tf` | 아래 §13.1 참조. `ecr_registry`는 `aws-ops` 신설로 해소됐고 **8종이 남았다** |

### 13.1 gitops 부트스트랩이 요구하는 output

`gitops/scripts/bootstrap-eks.sh:219`가 `terraform -chdir="$TF_DIR" output -json`으로
**디렉터리 하나**에서 전부 읽는다. 246–254행의 필수 목록 9종 중 하나라도 비면 `die`한다.

| gitops 요구 이름 | 현재 output | 루트 | 상태 |
|---|---|---|---|
| `aws_region` | 없음 | — | **신설 필요** |
| `aws_account_id` | 없음 | — | **신설 필요** |
| `ecr_registry` | `ecr_registry` | `aws-ops` | 해소 |
| `eks_cluster_name` | `cluster_name` | `aws-eks` | 이름 불일치 |
| `rds_address` | `db_address` | `aws-rds` | 이름 불일치 |
| `rds_port` | `db_port` | `aws-rds` | 이름 불일치 |
| `rds_master_user_secret_arn` | `master_user_secret_arn` | `aws-rds` | 이름 불일치 |
| `rds_app_secret_arn` | 없음 | — | **신설 필요** |
| `rds_bootstrap_db_name` | `db_name` | `aws-rds` | 이름만 불일치. 값은 같다 — 둘 다 RDS 인스턴스의 `DBName`이다 |
| (선택) `vpc_id` | `vpc_id` | `aws-core` | 해소 |
| (선택) `rds_app_db_username` | 없음 | — | 비어도 `die`하지 않음. 기본값 `bank_app` |

**이름 불일치보다 큰 문제가 있다.** 루트를 5개로 쪼갠 결과, 요구되는 9종이 `aws-ops`·`aws-eks`·
`aws-rds` **세 루트에 흩어져 있어 `--tf-dir` 하나로는 어느 쪽을 가리켜도 충족되지 않는다.**
루트 분리가 만들어낸 구조적 충돌이고, 이름만 고쳐서는 풀리지 않는다. 선택지는 셋이다.

1. **집계 루트를 둔다** — 세 루트를 `terraform_remote_state`로 읽어 9종을 그대로 내는 얇은 루트.
   스크립트는 손대지 않는다.
2. **스크립트를 여러 루트를 읽도록 고친다** — `TF_DIR`을 복수로 받아 병합. gitops 저장소 변경.
3. **`aws.env`에 직접 적는다** — 스크립트가 환경 파일 값을 우선하므로 가능하나, 손으로 유지해야 한다.

`rds_master_user_secret_arn`과 `rds_app_secret_arn`이 **같으면 스크립트가 거부한다**(272행).
애플리케이션 전용 시크릿을 따로 만들어야 하며, 현재 `aws-rds`에는 그 리소스가 없다.

**DB 이름이 바뀐 것도 같이 걸린다.** `aws-rds/main.tf:18`이 `db_name = "boadb"`인데
`gitops/k8s/overlays/dev/aws/env-config.properties:6`은 `BOOTSTRAP_DB_NAME=projectdb`다.
이 파일은 부트스트랩이 terraform output으로 **다시 렌더링**하므로(스크립트 415행) 실행하면
맞춰지지만, 저장소에 커밋된 값과 다르다는 점은 알고 있어야 한다.

**어느 선택지를 쓸지는 미정이다.** gitops 부트스트랩 실행 전에 정해야 한다.

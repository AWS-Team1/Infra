# Karpenter 수동 설치 및 Node Auto Scaling 검증

## 구성 흐름

```text
Helm으로 Karpenter Controller와 CRD 설치
  EC2NodeClass 적용
    NodePool 적용
      Pending Pod 발생
        Karpenter가 EC2 Node 생성
          Scheduler가 Pending Pod 배치
```

Terraform 인프라는 이미 구성됐다고 가정한다. Helm은 Karpenter Controller와 CRD를 설치할 때만 사용한다. 나머지는 기본 YAML 파일과 `kubectl apply -f`를 사용한다.

적용 환경:

| 항목 | 값 |
| --- | --- |
| AWS Region | `ap-northeast-2` |
| EKS Cluster | `boa-eks` |
| Kubernetes | `1.36` |
| Karpenter | `1.14.1` |
| Namespace | `karpenter` |
| ServiceAccount | `karpenter` |
| Controller | 2개 |

---

## 1. 설치

### Step 1. 도구 확인

```bash
aws --version
kubectl version --client
helm version
```

### Step 2. EKS 접속 설정

```bash
export AWS_REGION=ap-northeast-2
export EKS_CLUSTER=boa-eks
export KARPENTER_VERSION=1.14.1
export KARPENTER_NAMESPACE=karpenter

aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER"
```

접속 대상과 기존 Managed Node를 확인한다.

```bash
kubectl config current-context
kubectl get nodes -o wide
```

기존 노드가 `Ready`여야 한다. Karpenter Controller는 기존 Managed Node에서 실행된다.

### Step 3. Karpenter 설치

Public ECR의 기존 로그인 정보를 제거한다. 이미 로그아웃 상태여도 계속 진행한다.

```bash
helm registry logout public.ecr.aws 2>/dev/null || true
```

Karpenter Controller와 CRD를 설치한다.

```bash
helm upgrade --install karpenter \
  oci://public.ecr.aws/karpenter/karpenter \
  --version "$KARPENTER_VERSION" \
  --namespace "$KARPENTER_NAMESPACE" \
  --create-namespace \
  --set settings.clusterName="$EKS_CLUSTER" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=karpenter \
  --set replicas=2 \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait \
  --timeout 10m
```

### Step 4. 설치 확인

```bash
helm list -n "$KARPENTER_NAMESPACE"

kubectl rollout status deployment/karpenter \
  -n "$KARPENTER_NAMESPACE" \
  --timeout=5m

kubectl get pods -n "$KARPENTER_NAMESPACE" -o wide
```

Controller Pod 2개가 `Running`이어야 한다.

CRD를 확인한다.

```bash
kubectl get crd \
  nodepools.karpenter.sh \
  nodeclaims.karpenter.sh \
  ec2nodeclasses.karpenter.k8s.aws
```

세 CRD가 모두 조회되면 설치 완료다.

---

## 2. Karpenter 배포

적용 순서:

```text
ec2nodeclass.yaml
  nodepool.yaml
    Auto Scaling 시험
```

### Step 1. 파일 확인

```bash
cd karpenter-manual-deploy
ls -l
```

다음 파일이 있어야 한다.

```text
ec2nodeclass.yaml
nodepool.yaml
KARPENTER_INSTALL.md
```

### Step 2. EC2NodeClass 적용

먼저 EKS API 서버에서 YAML을 검증한다.

```bash
kubectl apply --dry-run=server -f ec2nodeclass.yaml
```

오류가 없으면 적용한다.

```bash
kubectl apply -f ec2nodeclass.yaml

kubectl wait \
  --for=condition=Ready \
  ec2nodeclass/default \
  --timeout=2m

kubectl get ec2nodeclass default -o wide
```

`Ready=True`가 된 후 NodePool을 적용한다.

### Step 3. NodePool 적용

```bash
kubectl apply --dry-run=server -f nodepool.yaml
kubectl apply -f nodepool.yaml

kubectl wait \
  --for=condition=Ready \
  nodepool/default \
  --timeout=2m

kubectl get nodepool default -o wide
```

최종 상태:

```bash
kubectl get ec2nodeclass,nodepool
```

두 리소스가 모두 `Ready=True`면 배포 완료다.

### Step 4. Node Auto Scaling 시험

> 이 시험은 실제 EC2 인스턴스를 생성하므로 비용이 발생한다.

시험용 Namespace와 Deployment를 만든다.

```bash
kubectl create namespace karpenter-test

kubectl create deployment inflate \
  --namespace karpenter-test \
  --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7 \
  --replicas=0

kubectl set resources deployment inflate \
  --namespace karpenter-test \
  --requests=cpu=1
```

CPU 1개를 요청하는 Pod 5개를 생성한다.

```bash
kubectl scale deployment inflate \
  --namespace karpenter-test \
  --replicas=5
```

각 명령은 별도 터미널에서 확인한다.

```bash
kubectl get pods -n karpenter-test -w
```

```bash
kubectl get nodeclaims,nodes -w
```

```bash
kubectl logs -n karpenter \
  -l app.kubernetes.io/name=karpenter \
  -c controller \
  -f
```

성공 흐름:

```text
일부 시험 Pod가 Pending
  NodeClaim 생성
    EC2 인스턴스 생성
      새 Node가 Ready
        Pending Pod가 Running
```

Karpenter가 만든 노드만 확인한다.

```bash
kubectl get nodes \
  -l karpenter.sh/nodepool=default \
  -o wide
```

### Step 5. Scale In 시험

시험 워크로드를 삭제한다.

```bash
kubectl delete namespace karpenter-test
```

현재 `consolidateAfter`는 `10m`이다. 노드가 빈 상태로 안정된 후 약 10분 이상 기다린다.

```bash
kubectl get nodeclaims,nodes -w
```

Karpenter가 만든 Node와 EC2가 삭제되면 성공이다. 기존 Managed Node Group은 삭제되지 않는다.

### Step 6. 배포 오류 확인

EC2NodeClass와 NodePool 상태:

```bash
kubectl describe ec2nodeclass default
kubectl describe nodepool default
```

Karpenter 로그:

```bash
kubectl logs -n karpenter \
  -l app.kubernetes.io/name=karpenter \
  -c controller \
  --tail=200
```

Pending Pod 원인:

```bash
kubectl get pods -A --field-selector=status.phase=Pending
kubectl describe pod <POD_NAME> -n <NAMESPACE>
```

---

## 3. 값 수정

배포 전에 YAML 값을 수정한다. 배포 후 수정했다면 같은 파일을 다시 `kubectl apply -f` 한다.

### 3-1. EC2NodeClass 값

파일: `ec2nodeclass.yaml`

| 값 | 현재 설정 | 역할 | 변경 시 주의점 |
| --- | --- | --- | --- |
| `amiSelectorTerms.alias` | `al2023@latest` | EKS 최적화 AL2023 선택 | 테스트용. 운영에서는 버전 고정 권장 |
| `role` | `boa-eks-node-role` | 새 Node의 IAM Role | Terraform Role 이름과 일치해야 함 |
| Subnet 탐색 태그 | `boa-eks` | 새 Node를 생성할 Subnet 선택 | Terraform 태그와 일치해야 함 |
| SG 탐색 태그 | `boa-eks` | Node에 연결할 SG 선택 | EKS Cluster SG 태그와 일치해야 함 |
| `volumeSize` | `50Gi` | Root EBS 크기 | 증가하면 스토리지 비용 증가 |
| `volumeType` | `gp3` | EBS 유형 | 특별한 이유가 없으면 유지 |

AMI 버전 고정 예시:

```yaml
amiSelectorTerms:
  - alias: al2023@vYYYYMMDD
```

`vYYYYMMDD`는 실제 사용할 AL2023 버전으로 바꿔야 한다.

### 3-2. NodePool 값

파일: `nodepool.yaml`

| 값 | 현재 설정 | 역할 | 변경 시 주의점 |
| --- | --- | --- | --- |
| Capacity Type | `on-demand` | On-Demand Node만 생성 | Spot 추가 시 중단 대응 필요 |
| Architecture | `amd64` | x86_64 인스턴스 사용 | ARM 이미지 검증 전 변경 금지 |
| OS | `linux` | Linux Node만 생성 | AL2023과 일치 |
| Instance Type | `t3.medium`, `t3.large` | 생성 가능한 EC2 유형 | 선택지가 적으면 용량 부족 가능 |
| `limits.cpu` | `"8"` | Karpenter Node 총 CPU 한도 | 기존 Managed Node는 제외 |
| `limits.memory` | `16Gi` | Karpenter Node 총 메모리 한도 | 기존 Managed Node는 제외 |
| `consolidationPolicy` | `WhenEmpty` | 빈 Node만 축소 | 실행 중인 일반 Pod는 옮기지 않음 |
| `consolidateAfter` | `10m` | 빈 Node 삭제 전 대기 | 너무 짧으면 생성·삭제 반복 가능 |
| `budgets.nodes` | `"1"` | 동시에 중단할 최대 Node | 소규모 환경 안정성 제한 |

인스턴스 유형 추가 예시:

```yaml
- key: node.kubernetes.io/instance-type
  operator: In
  values: ["t3.medium", "t3.large", "m6i.large"]
```

최대 용량 변경 예시:

```yaml
limits:
  cpu: "16"
  memory: 32Gi
```

### 3-3. 수정값 적용

EC2NodeClass:

```bash
kubectl apply --dry-run=server -f ec2nodeclass.yaml
kubectl apply -f ec2nodeclass.yaml
kubectl get ec2nodeclass default -o wide
```

NodePool:

```bash
kubectl apply --dry-run=server -f nodepool.yaml
kubectl apply -f nodepool.yaml
kubectl get nodepool default -o wide
```

전체 상태:

```bash
kubectl get nodepool,ec2nodeclass,nodeclaim
```

AMI, IAM Role, EBS, Subnet 또는 Security Group 설정을 변경하면 기존 Karpenter Node가 `Drifted` 상태가 되어 교체될 수 있다.

### 3-4. Karpenter 제거

먼저 NodePool을 삭제한다.

```bash
kubectl delete nodepool default
kubectl get nodeclaims,nodes -w
```

Karpenter Node와 EC2가 모두 삭제된 후 나머지를 제거한다.

```bash
kubectl delete ec2nodeclass default
helm uninstall karpenter -n karpenter
kubectl delete namespace karpenter
```

기존 Managed Node만 남았는지 확인한다.

```bash
kubectl get nodes -o wide
```

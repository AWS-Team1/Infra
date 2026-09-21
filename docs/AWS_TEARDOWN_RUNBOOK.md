# AWS 전체 철거 런북

이 문서는 Bank of Anthos AWS 환경을 내리고 다시 Terraform으로 만들 수 있도록 정리한 절차다. Windows에서는 SSH 접속만 하고, 나머지 명령은 모두 Code Server의 bash에서 Infra 저장소 루트를 기준으로 실행한다.

## 0. 삭제 범위

삭제한다.

- ArgoCD가 배포한 Kubernetes 리소스
- Karpenter NodePool과 노드
- DMS task, endpoint, replication instance, subnet group
- EKS와 관련 IAM·애드온
- RDS와 ElastiCache
- Ops ALB, Target Group, `argocd.bespinglobal.site` 레코드
- AWS 측 Site-to-Site VPN
- Terraform이 만든 subnet, NAT Gateway, Internet Gateway, 임시 bastion

보존한다.

- S3 Terraform state bucket
- 기존 VPC
- Route53 public/private hosted zone
- ACM 인증서
- SSH key pair
- ECR repository와 image
- DB/JWT/DMS Secrets Manager secret
- Code Server EC2
- 콘솔에서 만든 `DMSSecretManagerAccessRole-20260918`

## 1. 고정값

| 항목 | 값 |
|---|---|
| AWS 계정 | `769413326616` |
| AWS region | `ap-northeast-2` |
| Terraform state bucket | `boa-terraform-state-6416` |
| 기존 VPC | `vpc-0a36febf3057e5da0` |
| EKS cluster | `boa-eks` |
| Kubernetes namespace | `bank-of-anthos` |
| Code Server | `karfa@15.165.176.99` |
| Windows SSH key | `%USERPROFILE%\.ssh\final_codeserver.pem` |
| public hosted zone | `Z03791674GY6T60MVQ4V` |
| private hosted zone | `Z056721513V17DUDMWKXV` |
| ACM certificate | `arn:aws:acm:ap-northeast-2:769413326616:certificate/1c81ee2e-edbc-4a42-961d-816d571767ab` |

Code Server에 연결된 EC2 IAM role을 사용한다. 별도 AWS CLI profile은 지정하지 않는다.

```bash
export AWS_REGION=ap-northeast-2
export AWS_DEFAULT_REGION=ap-northeast-2
aws sts get-caller-identity
```

목적: Terraform과 AWS CLI가 올바른 계정을 사용하게 한다.

예상 결과: `Account`가 `769413326616`이다.

## 2. ArgoCD와 Karpenter 중지

EKS API public CIDR가 Code Server IP만 허용하므로 Windows CMD에서 Code Server로 접속한다.

```cmd
ssh -i "%USERPROFILE%\.ssh\final_codeserver.pem" karfa@15.165.176.99
```

목적: 삭제 중 ArgoCD가 리소스를 다시 만들지 못하게 한다.

예상 결과: Code Server의 bash prompt가 나타난다.

Code Server 안에서 실행한다.

```bash
kubectl -n argocd patch application boa-eks-root --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'

for app in $(kubectl -n argocd get applications -o name); do
  kubectl -n argocd patch "$app" --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
done

kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,AUTO-SYNC:.spec.syncPolicy.automated'
kubectl -n argocd scale statefulset argocd-application-controller --replicas=0
```

예상 결과: 모든 Application의 `AUTO-SYNC`가 `<none>`이고 Application Controller가 0 replica가 된다.

ALB 연결과 Karpenter 노드를 먼저 제거한다.

```bash
kubectl -n argocd delete targetgroupbinding argocd-server --ignore-not-found --wait --timeout=15m
kubectl delete nodepool default --ignore-not-found --wait=false
kubectl get nodeclaim
```

목적: ALB Target Group과 subnet ENI, Karpenter EC2가 EKS/Core 삭제를 막지 않게 한다.

예상 결과: `kubectl get nodeclaim`이 `No resources found`를 출력한다.

## 3. DMS 삭제

먼저 state 유무를 확인한다.

```bash
terraform -chdir=aws-dms init -reconfigure
terraform -chdir=aws-dms state list
```

목적: DMS가 Terraform 관리 대상인지 확인한다.

예상 결과: state에 DMS 리소스가 있으면 다음 명령으로 제거한다.

```bash
terraform -chdir=aws-dms destroy
```

state가 비었거나 콘솔에서 만든 DMS라면 아래 CLI 절차를 사용한다. ARN은 조회 결과를 복사한다.

```bash
aws dms describe-replication-tasks --region ap-northeast-2 --query "ReplicationTasks[].{Id:ReplicationTaskIdentifier,Status:Status,Arn:ReplicationTaskArn}" --output table
aws dms stop-replication-task --region ap-northeast-2 --replication-task-arn <TASK_ARN>
aws dms delete-replication-task --region ap-northeast-2 --replication-task-arn <TASK_ARN>
```

목적: CDC task를 먼저 중지하고 삭제한다. 이미 `failed` 또는 `stopped`이면 stop은 생략한다.

예상 결과: `describe-replication-tasks` 결과가 빈 배열이 된다.

```bash
aws dms describe-endpoints --region ap-northeast-2 --query "Endpoints[].{Id:EndpointIdentifier,Arn:EndpointArn}" --output table
aws dms delete-endpoint --region ap-northeast-2 --endpoint-arn <ENDPOINT_ARN>

aws dms describe-replication-instances --region ap-northeast-2 --query "ReplicationInstances[].{Id:ReplicationInstanceIdentifier,Status:ReplicationInstanceStatus,Arn:ReplicationInstanceArn}" --output table
aws dms delete-replication-instance --region ap-northeast-2 --replication-instance-arn <INSTANCE_ARN>
aws dms wait replication-instance-deleted --region ap-northeast-2 --replication-instance-arn <INSTANCE_ARN>
```

목적: endpoint와 replication instance를 제거한다.

예상 결과: endpoint와 instance 조회 결과가 빈 배열이다.

```bash
aws dms describe-replication-subnet-groups --region ap-northeast-2 --query "ReplicationSubnetGroups[].ReplicationSubnetGroupIdentifier" --output table
aws dms delete-replication-subnet-group --region ap-northeast-2 --replication-subnet-group-identifier <SUBNET_GROUP_ID>
```

목적: instance 삭제 후 남은 DMS subnet group을 제거한다.

예상 결과: DMS subnet group 조회 결과가 비어 있다.

## 4. DB bootstrap의 EKS 연결만 삭제

DB Secrets와 bootstrap IAM은 다음 재배포에 재사용하므로 전체 destroy하지 않는다.

```bash
terraform -chdir=aws-db-bootstrap init -reconfigure
terraform -chdir=aws-db-bootstrap destroy -target=aws_eks_pod_identity_association.db_bootstrap
```

목적: EKS 삭제를 막는 Pod Identity association만 제거한다.

예상 결과: `1 destroyed`이며 DB Secrets와 IAM role은 state에 남는다.

## 5. JWT Secret 보존 후 EKS 삭제

현재 JWT secret container가 `aws-eks` state에 있으므로 그대로 destroy하면 Secret도 삭제된다. 삭제 전에 state에서만 분리한다.

```bash
terraform -chdir=aws-eks init -reconfigure
terraform -chdir=aws-eks state rm module.eks.aws_secretsmanager_secret.jwt_private module.eks.aws_secretsmanager_secret.jwt_public
```

목적: `/boa/jwt/private`, `/boa/jwt/public`을 실제 AWS에 보존한다.

예상 결과: `Successfully removed 2 resource instance(s).`

클러스터 내부 객체는 EKS 삭제와 함께 사라지므로 API/Helm 조회가 destroy를 막을 때만 state에서 분리한다.

```bash
terraform -chdir=aws-eks state rm kubernetes_cluster_role_binding_v1.secrets_store_sync kubernetes_cluster_role_v1.secrets_store_sync module.aws_load_balancer_controller.helm_release.this module.aws_load_balancer_controller.kubernetes_service_account_v1.this
```

AWS 리소스만 대상으로 EKS를 삭제한다.

```bash
terraform -chdir=aws-eks destroy \
  -target=module.eks \
  -target=module.eks_iam \
  -target=module.aws_load_balancer_controller.aws_eks_pod_identity_association.this \
  -target=module.aws_load_balancer_controller.aws_iam_role_policy_attachment.this \
  -target=module.aws_load_balancer_controller.aws_iam_policy.this \
  -target=module.aws_load_balancer_controller.aws_iam_role.this
```

목적: Helm cache와 로컬 EKS API 접근 여부에 영향받지 않고 EKS 및 관련 AWS IAM을 제거한다.

예상 결과: node group 삭제 후 `boa-eks`가 사라지고 state에는 data source만 남는다. AWS가 node group을 지우는 데 10분가량 걸릴 수 있다.

> 재구축 때는 `aws-core` apply 후 `aws-eks` apply 전에 보존한 JWT Secret을 import해야 한다. 장기적으로는 JWT Secret을 `aws-db-bootstrap` 같은 영속 root로 옮기는 것이 더 단순하다.

```bash
terraform -chdir=aws-eks import module.eks.aws_secretsmanager_secret.jwt_private <PRIVATE_SECRET_ARN>
terraform -chdir=aws-eks import module.eks.aws_secretsmanager_secret.jwt_public <PUBLIC_SECRET_ARN>
```

## 6. RDS와 ElastiCache 삭제

```bash
terraform -chdir=aws-rds init -reconfigure
terraform -chdir=aws-rds destroy

terraform -chdir=aws-cache init -reconfigure
terraform -chdir=aws-cache destroy
```

목적: DB/cache와 subnet group, parameter group, 보안그룹, 모니터링 IAM을 제거한다.

예상 결과: 아래 조회가 빈 결과를 반환한다.

```bash
aws rds describe-db-instances --region ap-northeast-2 --query "DBInstances[?DBInstanceIdentifier=='boa-postgres'].DBInstanceIdentifier" --output text
aws elasticache describe-replication-groups --region ap-northeast-2 --query "ReplicationGroups[?contains(ReplicationGroupId, 'boa')].ReplicationGroupId" --output text
```

## 7. ECR을 보존하고 Ops ALB만 삭제

`aws-ops destroy` 전체 실행은 ECR까지 지우므로 사용하지 않는다.

```bash
terraform -chdir=aws-ops init -reconfigure
terraform -chdir=aws-ops destroy -target=module.ops_alb -target=aws_route53_record.argocd
```

목적: ECR repository/image는 유지하고 Ops ALB, Target Group, 보안그룹, ArgoCD DNS만 제거한다.

예상 결과: `11 destroyed`이며 `terraform -chdir=aws-ops state list`에는 `module.ecr` 리소스가 남는다.

## 8. AWS 측 VPN 삭제

이 단계는 GCP VPN tunnel을 `DOWN` 상태로 만든다. GCP 리소스 자체는 삭제하지 않는다.

```bash
aws ec2 describe-vpn-connections --region ap-northeast-2 --filters Name=state,Values=pending,available --query "VpnConnections[].{Id:VpnConnectionId,VGW:VpnGatewayId,CGW:CustomerGatewayId,Name:Tags[?Key=='Name']|[0].Value}" --output table
```

조회한 ID로 순서대로 실행한다.

```bash
aws ec2 delete-vpn-connection --region ap-northeast-2 --vpn-connection-id <VPN_ID>
aws ec2 delete-customer-gateway --region ap-northeast-2 --customer-gateway-id <CGW_ID>
aws ec2 detach-vpn-gateway --region ap-northeast-2 --vpn-gateway-id <VGW_ID> --vpc-id vpc-0a36febf3057e5da0
aws ec2 delete-vpn-gateway --region ap-northeast-2 --vpn-gateway-id <VGW_ID>
```

목적: AWS 측 cross-cloud VPN 리소스를 제거한다.

예상 결과: VPN connection, customer gateway, virtual private gateway 조회 결과가 비어 있다. `delete-vpn-gateway`는 attachment가 `detached`가 된 뒤 실행한다.

## 9. Core 삭제

VPN, EKS, ALB, RDS, cache가 모두 사라진 뒤 실행한다.

```bash
terraform -chdir=aws-core init -reconfigure
terraform -chdir=aws-core destroy
```

목적: Terraform이 만든 subnet, route table, NAT Gateway, EIP, IGW, 임시 bastion을 제거한다.

예상 결과: `aws-core` state가 비고 기존 VPC·private hosted zone·SSH key pair는 남는다.

## 10. 최종 검증

삭제 대상 확인:

```bash
aws eks list-clusters --region ap-northeast-2 --query "clusters[?contains(@, 'boa')]"
aws elbv2 describe-load-balancers --region ap-northeast-2 --query "LoadBalancers[?contains(LoadBalancerName, 'boa')].LoadBalancerName"
aws dms describe-replication-tasks --region ap-northeast-2 --query "ReplicationTasks[].ReplicationTaskIdentifier"
aws dms describe-endpoints --region ap-northeast-2 --query "Endpoints[].EndpointIdentifier"
aws dms describe-replication-instances --region ap-northeast-2 --query "ReplicationInstances[].ReplicationInstanceIdentifier"
aws rds describe-db-instances --region ap-northeast-2 --query "DBInstances[?contains(DBInstanceIdentifier, 'boa')].DBInstanceIdentifier"
aws elasticache describe-replication-groups --region ap-northeast-2 --query "ReplicationGroups[?contains(ReplicationGroupId, 'boa')].ReplicationGroupId"
```

예상 결과: 모두 빈 배열 또는 빈 문자열이다.

보존 대상 확인:

```bash
aws s3api head-bucket --bucket boa-terraform-state-6416
aws ec2 describe-vpcs --region ap-northeast-2 --vpc-ids vpc-0a36febf3057e5da0 --query "Vpcs[].State"
aws ecr describe-repositories --region ap-northeast-2 --query "repositories[?starts_with(repositoryName, 'boa-')].repositoryName"
aws secretsmanager list-secrets --region ap-northeast-2 --query "SecretList[?contains(Name, 'boa')].Name"
aws ec2 describe-instances --region ap-northeast-2 --instance-ids i-0f99d67d85fc7a472 --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,State:State.Name,Ip:PublicIpAddress}"
```

예상 결과: state bucket과 VPC가 존재하고 ECR·Secrets가 조회되며 `final_codeserver`가 `running`이다.

## 11. 2026-09-21 실행 결과

- EKS, Karpenter node, RDS, ElastiCache, DMS, Ops ALB, AWS VPN, Terraform 관리 Core 리소스 삭제 완료
- ECR, DB/JWT/DMS Secret, state bucket, 기존 VPC, Route53 zones, ACM, SSH key pair, Code Server 보존 확인
- `DMSSecretManagerAccessRole-20260918`은 Terraform 비관리 리소스이며 정책이 연결된 상태로 보존
- `aws-core`, `aws-rds`, `aws-cache` state는 비어 있음
- `aws-ops` state에는 ECR만, `aws-db-bootstrap` state에는 DB Secrets와 bootstrap IAM만 남음

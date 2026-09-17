# Argo CD AWS bootstrap root

Argo CD와 Bank of Anthos GitOps가 시작되기 전에 필요한 AWS 리소스를 소유합니다.
기존 root를 역참조해 적용 순서는 `aws-core → aws-rds/aws-ops/aws-eks → aws-cd-bootstrap`입니다.

이 root는 다음을 관리합니다.

- `/boa/database/app` Secrets Manager Secret 컨테이너(값은 GitOps 스크립트가 주입)
- DB bootstrap 전용 IAM Role/inline policy/EKS Pod Identity Association
- `db.boa.internal` Private DNS
- `argocd.bespinglobal.site` Public DNS

`HARD-CODED` 주석이 붙은 값은 다른 계정/리전/도메인에서 재사용할 때 반드시 검토합니다.

```bash
terraform -chdir=aws-cd-bootstrap init
terraform -chdir=aws-cd-bootstrap plan -out=tfplan
terraform -chdir=aws-cd-bootstrap apply tfplan
```

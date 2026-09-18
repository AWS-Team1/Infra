# Argo CD AWS bootstrap root

Bank of Anthos GitOps가 시작되기 전에 필요한 DB bootstrap AWS 리소스를 소유합니다.
적용 순서는 `aws-core → aws-rds/aws-eks → aws-db-bootstrap`입니다.

이 root는 다음을 관리합니다.

- `/boa/database/app`, `/boa/database/accounts`, `/boa/database/ledger` Secret과 로컬 캐시 비밀번호 Version
- DB bootstrap 전용 IAM Role/inline policy/EKS Pod Identity Association
- `db.boa.internal` Private DNS
- `argocd.bespinglobal.site` Public DNS

`HARD-CODED` 주석이 붙은 값은 다른 계정/리전/도메인에서 재사용할 때 반드시 검토합니다.

```bash
for name in app accounts ledger; do
  SECRET_NAME="/boa/database/$name" bash gitops/02_scripts/prepare-database-secret.sh
done
terraform -chdir=Infra/aws-db-bootstrap init
terraform -chdir=Infra/aws-db-bootstrap plan -out=tfplan
terraform -chdir=Infra/aws-db-bootstrap apply tfplan
```

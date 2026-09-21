# Argo CD AWS bootstrap root

Bank of Anthos GitOps가 시작되기 전에 필요한 DB bootstrap AWS 리소스를 소유합니다.
적용 순서는 `aws-core → aws-rds/aws-eks → aws-db-bootstrap`입니다.

이 root는 다음을 관리합니다.

- `/boa/database/app`, `/boa/database/accounts`, `/boa/database/ledger` Secret과 비밀번호 Version
- DB bootstrap 전용 IAM Role/inline policy/EKS Pod Identity Association
- `db.boa.internal` Private DNS
- `argocd.bespinglobal.site` Public DNS

`HARD-CODED` 주석이 붙은 값은 다른 계정/리전/도메인에서 재사용할 때 반드시 검토합니다.

```bash
terraform -chdir=Infra/aws-db-bootstrap init
terraform -chdir=Infra/aws-db-bootstrap plan -out=tfplan
terraform -chdir=Infra/aws-db-bootstrap apply tfplan
```

비밀번호는 ephemeral `random_password`가 apply 중에만 생성하고
`secret_string_wo`로 Secrets Manager에 전달한다. 평문은 plan/state/파일에 남지 않는다.
앱 DB 계정은 자동 회전하지 않는다. 운영 정책상 회전이 필요할 때만 `main.tf`의
`secret_string_wo_version`을 바꿔 apply하고 DB bootstrap Job을 다시 실행한다.

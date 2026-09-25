# AWS Terraform re-lifecycle migration plan

The requested design document at
docs/specs/2026-09-24-terraform-root-relifecycle-design.md does not exist on
Infra dev commit 092d97580d01c1865bd8cc42ddd2d62f7ce606f8. This plan is based
on the fetched Infra and GitOps dev branches, remote state, and read-only AWS
inventory captured on 2026-09-25.

No command in this document is part of the normal Apply or Destroy workflow.
Do not run Terraform Apply between destination import and source state removal.
The listed backup is an audit snapshot only: remote core/RDS/EKS serials changed after
it was taken. Before any authorized migration, create a new read-only state-pull backup,
re-run the inventory and plans, and pass that new directory as `STATE_BACKUP_DIR`.

| Resource | Source root/address | Physical AWS/K8s ID | Destination root/address | Migration method | Replacement expected? |
| --- | --- | --- | --- | --- | --- |
| JWT public Secret | aws-eks / module.eks.aws_secretsmanager_secret.jwt_public | arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/jwt/public-1HxMV3 | persistent / aws_secretsmanager_secret.jwt_public | Import destination, verify ARN, remove source state | No |
| JWT private Secret | aws-eks / module.eks.aws_secretsmanager_secret.jwt_private | arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/jwt/private-oHogZ3 | persistent / aws_secretsmanager_secret.jwt_private | Import destination, verify ARN, remove source state | No |
| App DB Secret | aws-db-bootstrap / aws_secretsmanager_secret.app_database | arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/app-jFdqLv | persistent / aws_secretsmanager_secret.app_database | Import destination, verify ARN, remove source state | No |
| Accounts DB Secret | aws-db-bootstrap / aws_secretsmanager_secret.accounts_database | arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/accounts-z9LhFP | persistent / aws_secretsmanager_secret.accounts_database | Import destination, verify ARN, remove source state | No |
| Ledger DB Secret | aws-db-bootstrap / aws_secretsmanager_secret.ledger_database | arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:/boa/database/ledger-9TXa7G | persistent / aws_secretsmanager_secret.ledger_database | Import destination, verify ARN, remove source state | No |
| App DB Secret version | aws-db-bootstrap / aws_secretsmanager_secret_version.app_database | app-jFdqLv, version terraform-BIUKZyCyMrT2PeX9qIVq8EWdx2 | persistent / aws_secretsmanager_secret_version.app_database | Import destination, verify version ID, remove source state | No; stop if plan creates a version |
| Accounts DB Secret version | aws-db-bootstrap / aws_secretsmanager_secret_version.accounts_database | accounts-z9LhFP, version terraform-yQT8QF7doEP7QnzxuBP8RkbTpv | persistent / aws_secretsmanager_secret_version.accounts_database | Import destination, verify version ID, remove source state | No; stop if plan creates a version |
| Ledger DB Secret version | aws-db-bootstrap / aws_secretsmanager_secret_version.ledger_database | ledger-9TXa7G, version terraform-nbAdZx8hhfb3PE4lk0uqu1SWlN | persistent / aws_secretsmanager_secret_version.ledger_database | Import destination, verify version ID, remove source state | No; stop if plan creates a version |
| LBC ServiceAccount | aws-eks / module.aws_load_balancer_controller.kubernetes_service_account_v1.this | kube-system/aws-load-balancer-controller | aws-eks-platform / module.aws_load_balancer_controller.kubernetes_service_account_v1.this | Import destination, verify UID, remove source state | No |
| LBC Helm release | aws-eks / module.aws_load_balancer_controller.helm_release.this | kube-system/aws-load-balancer-controller | aws-eks-platform / module.aws_load_balancer_controller.helm_release.this | Import destination, verify release, remove source state | No |
| CSI sync ClusterRole | aws-eks / kubernetes_cluster_role_v1.secrets_store_sync | secretprovidersyncing-role | aws-eks-platform / kubernetes_cluster_role_v1.secrets_store_sync | Import destination, verify name, remove source state | No |
| CSI sync ClusterRoleBinding | aws-eks / kubernetes_cluster_role_binding_v1.secrets_store_sync | secretprovidersyncing-rolebinding | aws-eks-platform / kubernetes_cluster_role_binding_v1.secrets_store_sync | Import destination, verify name, remove source state | No |

Verified state backup:

    C:\Users\박지호\Documents\Codex\최종프로젝트\artifacts\state-backup\20260925-103457

S3 bucket versioning is enabled.

Print the exact commands without changing state:

    bash scripts/migrate-aws-relifecycle-state.sh --print

Execution is intentionally guarded and is not authorized in the current run:

    export STATE_BACKUP_DIR=/verified/backup/path
    export CONFIRM_STATE_MIGRATION=MIGRATE-AWS-RELIFECYCLE
    bash scripts/migrate-aws-relifecycle-state.sh --execute

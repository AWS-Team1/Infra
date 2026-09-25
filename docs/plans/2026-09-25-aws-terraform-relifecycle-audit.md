# AWS Terraform re-lifecycle audit

Date: 2026-09-25 (Asia/Seoul)

## Safety boundary

This audit did not run Terraform apply/destroy/import/state rm/state mv, did not
change an AWS or Kubernetes resource, and did not commit, push, or create a PR.
The GitOps renderer ran only in a detached temporary worktree.

## Source revisions

- Infra base: `origin/dev-0922` at `89e4fad454ebfaec328218fc8b08a80b01ccc9b1`
- Parent dev: `origin/dev` at `092d97580d01c1865bd8cc42ddd2d62f7ce606f8`
- GitOps: `origin/dev` at `607572f48b52797b4f4e1002a740546da0483c5e`
- Local Infra branch: `refactor/aws-terraform-relifecycle-dev0922`
- The requested `docs/specs/2026-09-24-terraform-root-relifecycle-design.md` was not present.

`dev-0922` contains all of `dev` and is nine commits ahead. Relative to `dev`, it
changes 22 files: Serverless Valkey ingress expands from port 6379 to 6379-6380,
while the remaining changes cover GCP database bootstrap identity, Cloud SQL Secret
documentation/wiring, reproducible rebuild behavior, regional GKE node sizing, and
provider/lockfile cleanup. Those base changes are preserved and are not part of this
AWS re-lifecycle patch.

## Dual execution contract

The same Terraform roots now support both execution identities:

- GitHub Actions assumes `arn:aws:iam::769413326616:role/boa-github-terraform-dev`.
- Code Server uses the EC2 instance role `arn:aws:iam::769413326616:role/CodeServerEc2Role`.
- Both roles already exist in the live EKS access entries, have
  `AmazonEKSClusterAdminPolicy`, and are present in the current Terraform state.
- All roots consume the local `env` module, so no GitHub-only `-var-file` is required.
- Embedded backend bootstrap values allow ordinary `terraform init` in a fresh Code Server clone;
  CI passes the matching `env/backend.hcl` values and verifies that they remain identical.

A fresh-data-directory simulation successfully ran plain `terraform init` and
`terraform validate` for all eight roots. Plain `terraform plan -refresh=false` in
`aws-core` completed with no changes and without a variable file.

## Read-only state backup

Backup directory:

```text
C:\Users\박지호\Documents\Codex\최종프로젝트\artifacts\state-backup\20260925-103457
```

| root | state key | serial | lineage | resources |
|---|---|---:|---|---:|
| aws-core | aws/core/terraform.tfstate | 34 | 977816cc-c677-9898-ec4e-3116561d28e0 | 29 |
| aws-rds | aws/rds/terraform.tfstate | 30 | 2a981c20-c513-7679-6b46-480469e43d61 | 10 |
| aws-cache | aws/cache/terraform.tfstate | 48 | a8d901ac-2a8e-b648-ed65-9588fb41fb47 | 8 |
| aws-ops | aws/ops/terraform.tfstate | 30 | 51b82a87-e15d-f31e-6559-9efc550b73a7 | 13 |
| aws-eks | aws/eks/terraform.tfstate | 73 | 4df29c96-92f9-250e-ae2b-051f6bdf4844 | 51 |
| aws-db-bootstrap | aws/db-bootstrap/terraform.tfstate | 10 | 6ef42349-e6f8-1631-7edc-ebc169ed2687 | 11 |

S3 bucket versioning is enabled. A later read-only comparison found external updates
after this backup: `aws-core` serial 35, `aws-rds` serial 32, and `aws-eks` serial 74.
The latest changed snapshots report Terraform 1.16.1 and were written before the local
Code Server simulation, which used Terraform 1.15.8. Core and RDS retained the same
resource addresses and physical IDs; EKS added the existing `CodeServerEc2Role` access
entry and Cluster Admin policy association. The migration must therefore take a fresh
`terraform state pull` backup and regenerate its preflight immediately before execution.
No object exists under `aws/persistent/` or `aws/eks-platform/`, confirming that the
destination states were not created.

## State versus live AWS

The AWS account was verified as `769413326616` using profile `team1`.
The state IDs and live APIs agree for the lifecycle-critical resources:

| Area | Live identifier/status | Result |
|---|---|---|
| EKS | `arn:aws:eks:ap-northeast-2:769413326616:cluster/boa-eks`, ACTIVE, 1.36 | Matches state |
| EKS node group | `boa-eks-node-group`, ACTIVE | Matches state |
| EKS add-ons | vpc-cni, coredns, kube-proxy, EBS CSI, Pod Identity Agent, ASCP | Match state |
| RDS | `arn:aws:rds:ap-northeast-2:769413326616:db:boa-postgres`, available, PostgreSQL 16.14 | Matches state |
| RDS managed Secret | `arn:aws:secretsmanager:ap-northeast-2:769413326616:secret:rds!db-5c35cfa1-4185-4b4e-8eb5-523c6ba54615-71VtfE` | Live value differs from stale GitOps render input |
| Ops ALB | `arn:aws:elasticloadbalancing:ap-northeast-2:769413326616:loadbalancer/app/boa-ops-alb/43412f29a6d68c2f` | Matches state |
| Argo CD target group | `arn:aws:elasticloadbalancing:ap-northeast-2:769413326616:targetgroup/boa-argocd-tg/1d027ee21cf38765` | Matches state |
| Ops ALB security group | `sg-093e300979b480d12` | Matches state |
| JWT/DB Secrets | Five container ARNs and three DB version IDs in the migration table | Match state and AWS |
| Pod Identity | LBC, Karpenter, app, DB bootstrap, and EBS CSI associations | Match state and AWS |

The EKS public endpoint currently allows only `15.165.176.99/32`; the audit host was
`1.232.68.59`. Therefore live Kubernetes object reads timed out. Kubernetes ownership
was cross-checked from Terraform state and GitOps source, but the API objects could not
be independently queried from this host without mutating the endpoint CIDR.

## Pre-migration plans

These plan counts were captured before the external state updates above and are retained
as evidence, not as an execution-time approval. Re-run every plan against a fresh backup
before migration.

| root | Add | Change | Destroy | Interpretation |
|---|---:|---:|---:|---|
| persistent | 8 | 0 | 0 | Expected empty destination before import |
| aws-core | 0 | 0 | 0 | Clean |
| aws-rds | 0 | 0 | 0 | Clean |
| aws-cache | 4 | 1 | 1 | Existing state drift; destructive and outside this refactor |
| aws-ops | 0 | 0 | 0 | Clean |
| aws-db-bootstrap | 0 | 0 | 6 | Expected source removals before state migration |
| aws-eks-platform | 4 | 0 | 0 | Expected empty destination before import (`-refresh=false`) |
| aws-eks | 0 | 1 | 2 | Partial only; old Kubernetes/Helm state cannot be decoded/refreshed by the AWS-only root |

On the `dev-0922` base, the cache plan would replace ElastiCache user `redis` with
`boa-app`, create a random password and `/boa/valkey/credentials` Secret/version, and
update the user group. Its 6379-6380 security-group change is already aligned and no
longer appears in the plan. A Secret with that name already exists live. The safe apply
helper rejects the delete/replace, so this drift blocks a normal end-to-end Apply until
the Valkey owner decides the intended ownership/migration.

The `aws-eks` partial plan is expected before migration: two JWT Secret containers move
to `persistent`, and four Kubernetes/Helm addresses move to `aws-eks-platform`. A complete
post-migration plan was not run because the current execution forbids state mutation.

## Historical GitOps renderer dry run

The existing renderer changed only the allowed generated files:

- `03_manifests/eks/shared/secrets.yaml`
- `manual/eks/argocd-exposure/targetgroupbinding.yaml`
- `manual/eks/secrets.yaml`

It replaced the stale RDS Secret ARN, target-group ARN, and ALB security-group ID with
the current live values. `git diff --check` passed. No GitOps commit or push was made.
This was audit evidence only. GitOps checkout/render/commit, Argo CD bootstrap, Root
Application sync, Karpenter, and application deployment are excluded from the final
AWS Terraform Apply/Destroy workflows and remain manual Code Server/operations tasks.

## Validation

- `terraform fmt -recursive -check`: passed
- `terraform validate`: passed for all eight roots
- Workflow YAML parsing: passed
- Bash syntax checks for all helper scripts: passed
- `git diff --check`: passed (only Windows LF/CRLF notices)
- Normal workflows contain no Terraform import/state rm/state mv, `-target`, or resource-address orchestration
- Migration script `--print`: exercised; execution mode was not run

## External configuration not verifiable

GitHub CLI authentication was invalid and the browser session was signed out, so the
`dev-infra` environment settings could not be confirmed. The workflows require:

- Variables: `AWS_ROLE_ARN`, `AWS_REGION`
- No custom GitOps or Argo CD Secret is referenced by the AWS Terraform workflows.

## Verdict

**BLOCKED** for an end-to-end repeatable Apply/Destroy cycle. The local refactor and
migration package are ready for review, but the authorized run intentionally did not
perform the migration, Kubernetes live verification is blocked by the endpoint CIDR,
GitHub settings are unverified, and the pre-existing `aws-cache` replacement/conflicting
Secret drift must be resolved by the Valkey owner.

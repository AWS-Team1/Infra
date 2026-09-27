# GCP infrastructure observability

`gcp-observability`의 GKE/애플리케이션 관측 수명주기와 분리된 Terraform
root입니다. Cloud SQL, external Application Load Balancer, HA VPN, Cloud NAT,
Cloud Storage의 Cloud Monitoring dashboard만 소유합니다.

Monitoring filter를 사용하므로 resource ID를 tfvars나 remote state로 전달하지
않습니다. `monitoring.googleapis.com` API는 플랫폼 또는 기존 observability
root에서 활성화되어 있어야 합니다.

```bash
terraform init
terraform plan
terraform apply
terraform output -raw dashboard_url
```

# AWS infrastructure observability

`aws-observability`의 EKS/애플리케이션 관측 수명주기와 분리된 Terraform root입니다.
RDS, ALB, NAT Gateway, Site-to-Site VPN, DMS, ElastiCache Serverless, S3의
CloudWatch dashboard만 소유합니다.

CloudWatch SEARCH를 사용하므로 resource ID를 tfvars나 remote state로 전달하지
않습니다. 단, SEARCH는 최근 2주 안에 데이터가 발행된 metric만 찾습니다.

```bash
terraform init -backend-config=../env/backend.hcl
terraform plan
terraform apply
terraform output -raw dashboard_url
```

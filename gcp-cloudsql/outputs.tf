# aws-dms 루트가 대상 엔드포인트를 만들 때 쓴다.
# GCP 구조가 아직 유동적이라 aws-dms 는 이 값을 remote_state 가 아니라
# tfvars 로 받는다. 여기서는 값을 꺼내 보기 위한 출력이다.

output "private_ip_address" {
  value = module.cloudsql.private_ip_address
}

output "instance_name" {
  value = module.cloudsql.instance_name
}

output "connection_name" {
  value = module.cloudsql.connection_name
}

output "database_names" {
  value = module.cloudsql.database_names
}

output "dms_username" {
  value = module.cloudsql.dms_username
}

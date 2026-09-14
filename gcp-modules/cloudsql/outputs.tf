# aws-dms 가 대상 엔드포인트를 만들 때 쓴다.
output "private_ip_address" {
  value = google_sql_database_instance.main.private_ip_address
}

output "instance_name" {
  value = google_sql_database_instance.main.name
}

output "connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "database_names" {
  value = [for d in google_sql_database.app : d.name]
}

output "dms_username" {
  value = google_sql_user.dms.name
}

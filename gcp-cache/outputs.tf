output "host" {
  value = one(local.valkey_discovery_endpoints).ip_address
}

output "port" {
  value = one(local.valkey_discovery_endpoints).port
}

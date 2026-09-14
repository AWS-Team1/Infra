output "aws_vpn_gateway_id" {
  value = aws_vpn_gateway.main.id
}

# 런북에서 터널 상태를 확인할 때 쓴다.
output "aws_vpn_connection_ids" {
  value = { for k, v in aws_vpn_connection.gcp : k => v.id }
}

output "gcp_ha_vpn_gateway_name" {
  value = google_compute_ha_vpn_gateway.main.name
}

output "gcp_vpn_tunnel_names" {
  value = { for k, v in google_compute_vpn_tunnel.main : k => v.name }
}

# AWS 쪽 터널 외부 IP. 방화벽·감사 확인용.
output "aws_tunnel_outside_ips" {
  value = local.aws_tunnel_ips
}

output "aws_vpn_connection_ids" {
  value = module.vpn.aws_vpn_connection_ids
}

output "gcp_vpn_tunnel_names" {
  value = module.vpn.gcp_vpn_tunnel_names
}

# 런북에서 터널 상태를 확인할 때 쓴다.
output "aws_tunnel_outside_ips" {
  value = module.vpn.aws_tunnel_outside_ips
}

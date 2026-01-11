output "server_id" {
  description = "Hetzner Robot server ID."
  value       = var.server_id
}

output "server_ip" {
  description = "Primary server IP address."
  value       = data.hrobot_server.server.server_ip
}

output "server_name" {
  description = "Server name."
  value       = data.hrobot_server.server.server_name
}

output "server_status" {
  description = "Server status."
  value       = data.hrobot_server.server.status
}

output "server_product" {
  description = "Server product model."
  value       = data.hrobot_server.server.product
}

output "server_datacenter" {
  description = "Server datacenter location."
  value       = data.hrobot_server.server.datacenter
}

output "ssh_key_fingerprint" {
  description = "Fingerprint of the registered SSH key."
  value       = var.ssh_key_fingerprint
}

output "node_ip" {
  description = "Private IP address on vSwitch network."
  value       = var.node_ip
}

output "connection_info" {
  description = "SSH connection information."
  value = {
    host = data.hrobot_server.server.server_ip
    port = var.ssh_port
    user = "root"
  }
}

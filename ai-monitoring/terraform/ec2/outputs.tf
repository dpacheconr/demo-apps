output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.aim_demo.id
}

output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.aim_demo.public_ip
}

output "owner_slug" {
  description = "Owner slug derived from email, used for resource naming"
  value       = local.owner_slug
}

output "private_key_path" {
  description = "Path to the auto-generated SSH private key"
  value       = local_file.private_key.filename
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.aim_demo.public_ip}"
}

output "ssh_tunnel_command" {
  description = "SSH tunnel command — forwards all service ports to localhost"
  value       = "ssh -i ${local_file.private_key.filename} -L 8501:localhost:8501 -L 8089:localhost:8089 -L 8001:localhost:8001 -L 8002:localhost:8002 -N ubuntu@${aws_instance.aim_demo.public_ip}"
}

output "flask_ui_url" {
  description = "Flask UI (via SSH tunnel)"
  value       = "http://localhost:8501"
}

output "locust_ui_url" {
  description = "Locust load testing UI (via SSH tunnel)"
  value       = "http://localhost:8089"
}

output "ai_agent_url" {
  description = "AI Agent API (via SSH tunnel)"
  value       = "http://localhost:8001"
}

output "mcp_server_url" {
  description = "MCP Server API (via SSH tunnel)"
  value       = "http://localhost:8002"
}

output "setup_log_command" {
  description = "Command to tail the setup log on the instance"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.aim_demo.public_ip} 'tail -f /var/log/aim-demo-setup.log'"
}

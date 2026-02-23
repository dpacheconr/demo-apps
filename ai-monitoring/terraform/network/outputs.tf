output "vpc_id" {
  description = "VPC ID — paste this into your EC2 env-*.tfvars"
  value       = aws_vpc.aim_demo.id
}

output "subnet_id" {
  description = "Public subnet ID — paste this into your EC2 env-*.tfvars"
  value       = aws_subnet.public.id
}

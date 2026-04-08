###############################################################################
# infra/outputs.tf
#
# PURPOSE: Exposes key values after terraform apply. These are used to:
#   - Connect to the EC2 instance via SSH
#   - Configure the application's database connection string
#   - Reference the VPC in future Terraform workspaces
#
# Run `terraform output` at any time to retrieve these values.
# Run `terraform output -json` to get machine-readable output for scripts.
###############################################################################

output "vpc_id" {
  description = "ID of the VaultBridge VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "ec2_instance_id" {
  description = "EC2 instance ID of the application server."
  value       = aws_instance.app_server.id
}

output "ec2_public_ip" {
  description = "Elastic IP address of the application server. Use this for SSH and DNS."
  value       = aws_eip.app_server.public_ip
}

output "ec2_ssh_command" {
  description = "Ready-to-use SSH command to connect to the application server."
  value       = "ssh -i ~/.ssh/vaultbridge_dev ec2-user@${aws_eip.app_server.public_ip}"
}

output "rds_endpoint" {
  description = "RDS instance endpoint (host:port). Use in your application's DB connection string."
  value       = aws_db_instance.postgres.endpoint
}

output "rds_db_name" {
  description = "Name of the initial database created on the RDS instance."
  value       = aws_db_instance.postgres.db_name
}

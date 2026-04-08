###############################################################################
# infra/outputs.tf
#
# Run `terraform output` after apply to retrieve these values.
# Run `terraform output -json` for machine-readable output.
# Run `terraform output db_secret_arn` to get the ARN for your .env file.
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
  description = "Elastic IP address of the application server."
  value       = aws_eip.app_server.public_ip
}

output "ec2_ssh_command" {
  description = "Ready-to-use SSH command to connect to the application server."
  value       = "ssh -i ~/.ssh/vaultbridge_dev ubuntu@${aws_eip.app_server.public_ip}"
}

output "rds_endpoint" {
  description = "RDS instance endpoint. Copy the host portion into your .env DB_HOST."
  value       = aws_db_instance.postgres.endpoint
}

output "rds_db_name" {
  description = "Name of the initial database on the RDS instance."
  value       = aws_db_instance.postgres.db_name
}

output "db_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret holding DB credentials. Copy into .env DB_SECRET_ARN."
  value       = try(aws_db_instance.postgres.master_user_secret[0].secret_arn, "not-yet-available — re-run terraform output after apply")
}

output "db_secret_name" {
  description = "KMS key ARN used to encrypt the RDS-managed secret."
  value       = module.secrets.kms_key_arn
}

output "ec2_iam_role_arn" {
  description = "ARN of the IAM role attached to the EC2 instance."
  value       = module.iam.ec2_role_arn
}

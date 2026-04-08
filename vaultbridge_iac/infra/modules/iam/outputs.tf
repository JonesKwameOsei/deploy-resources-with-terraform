###############################################################################
# modules/iam/outputs.tf
###############################################################################

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile. Reference this in aws_instance.iam_instance_profile."
  value       = aws_iam_instance_profile.ec2_secrets.name
}

output "ec2_role_name" {
  description = "Name of the EC2 IAM role. Used to attach additional policies at root level."
  value       = aws_iam_role.ec2_secrets.name
}

output "ec2_role_arn" {
  description = "ARN of the EC2 IAM role."
  value       = aws_iam_role.ec2_secrets.arn
}

output "rds_monitoring_role_arn" {
  description = "ARN of the RDS Enhanced Monitoring role. Reference this in aws_db_instance.monitoring_role_arn."
  value       = aws_iam_role.rds_monitoring.arn
}

output "vpc_flow_logs_role_arn" {
  description = "ARN of the IAM role used by VPC Flow Logs to write to CloudWatch."
  value       = aws_iam_role.vpc_flow_logs.arn
}

###############################################################################
# modules/secrets/outputs.tf
###############################################################################

output "kms_key_arn" {
  description = "ARN of the KMS CMK encrypting the RDS-managed secret, CloudWatch Logs, and Performance Insights."
  value       = var.kms_key_arn != "" ? var.kms_key_arn : aws_kms_key.secrets[0].arn
}

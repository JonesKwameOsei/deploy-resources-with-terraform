###############################################################################
# modules/iam/variables.tf
###############################################################################

variable "project_name" {
  description = "Project identifier used in resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the secret. Required for kms:Decrypt permission."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all IAM resources."
  type        = map(string)
  default     = {}
}

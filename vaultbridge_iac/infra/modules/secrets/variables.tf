###############################################################################
# modules/secrets/variables.tf
###############################################################################

variable "project_name" {
  description = "Project identifier used in resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key. A new CMK is created if empty."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources in this module."
  type        = map(string)
  default     = {}
}

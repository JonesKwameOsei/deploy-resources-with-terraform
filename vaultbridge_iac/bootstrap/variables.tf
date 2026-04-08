###############################################################################
# bootstrap/variables.tf
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy bootstrap resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used in resource naming."
  type        = string
  default     = "vaultbridge"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "global_bool" {
  description = "Set true as a global selector"
  type = bool
  default = true
}

variable "algorithm_key" {
  description = "Key for algorithm"
  type = string
  default = "AES256"
}

variable "versioning_status" {
  description = "Status of S3 bucket versioning"
  type = string
  default = "Enabled"
}

variable "byte_length" {
  description = "Byte size length"
  type        = number
  default     = 4
}

variable "resource_tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
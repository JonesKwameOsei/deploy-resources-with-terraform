###############################################################################
# bootstrap/main.tf
#
# PURPOSE: One-time setup. Creates the S3 bucket that the main infra workspace
#          uses for remote state storage and S3-native locking.
#
# LOCKING: State locking is handled by S3 natively via use_lockfile = true in
#          infra/backend.tf. DynamoDB-based locking is deprecated as of recent
#          Terraform versions and has been removed from this project.
#
# IMPORTANT: This workspace uses LOCAL state intentionally. You cannot store
#            state in an S3 bucket that Terraform itself is creating.
#
# RUN ONCE: After applying, copy the bucket name from outputs into
#           infra/backend.tf, then never run this workspace again unless
#           you are rebuilding from scratch.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.resource_tags
  }
}

###############################################################################
# S3 Bucket — Remote State Storage
###############################################################################

resource "aws_s3_bucket" "terraform_state" {
  # Bucket names must be globally unique. The random suffix achieves this.
  bucket = "${var.project_name}-tfstate-${var.environment}-${random_id.suffix.hex}"

  # Prevent accidental deletion of this bucket which would destroy all state.
  lifecycle {
    prevent_destroy = var.global_bool
  }
}

resource "random_id" "suffix" {
  byte_length = var.byte_length
}

# Enable versioning so every state file change is preserved and recoverable.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = var.versioning_status
  }
}

# Encrypt state at rest. State files can contain sensitive values.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.algorithm_key
    }
  }
}

# Block all public access. State files must never be publicly readable.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = var.global_bool
  block_public_policy     = var.global_bool
  ignore_public_acls      = var.global_bool
  restrict_public_buckets = var.global_bool
}

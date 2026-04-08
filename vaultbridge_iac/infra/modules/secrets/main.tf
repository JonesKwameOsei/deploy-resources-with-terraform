###############################################################################
# modules/secrets/main.tf
#
# PURPOSE: Provisions the KMS CMK used to encrypt the RDS-managed secret.
#
# HOW IT WORKS:
#   RDS native rotation (manage_master_user_password = true) handles credential
#   generation and rotation entirely. AWS stores the secret in Secrets Manager
#   and rotates it automatically — no Lambda, no Terraform-managed password.
#
#   This module's only job is to create and export the KMS key so that:
#     - The RDS-managed secret is encrypted with our CMK (not AWS-managed key)
#     - CloudWatch Logs and Performance Insights share the same key
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  secret_name = "${var.project_name}/${var.environment}/db-credentials"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "kms_key_policy" {
  count = var.kms_key_arn == "" ? 1 : 0

  # Root account retains full key administration
  statement {
    sid    = "EnableRootAdmin"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Secrets Manager needs GenerateDataKey + Decrypt to store and retrieve secrets
  statement {
    sid    = "AllowSecretsManager"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["secretsmanager.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = ["*"]
  }

  # CloudWatch Logs needs these actions to encrypt a log group
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  # RDS needs Decrypt + GenerateDataKey for Performance Insights encryption
  statement {
    sid    = "AllowRDS"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "secrets" {
  count = var.kms_key_arn == "" ? 1 : 0

  description             = "CMK for ${var.project_name} — Secrets Manager, CloudWatch Logs, RDS PI — ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy[0].json

  tags = merge(var.tags, {
    Name = "${var.project_name}-secrets-cmk-${var.environment}"
  })
}

resource "aws_kms_alias" "secrets" {
  count = var.kms_key_arn == "" ? 1 : 0

  name          = "alias/${var.project_name}-secrets-${var.environment}"
  target_key_id = aws_kms_key.secrets[0].key_id
}

# ── Secrets Manager Secret ────────────────────────────────────────────────────
# NOTE: The actual Secrets Manager secret is created and managed by RDS when
# manage_master_user_password = true is set on aws_db_instance. The ARN is
# available via aws_db_instance.postgres.master_user_secret[0].secret_arn.
# This module's sole responsibility is the KMS key used to encrypt it.

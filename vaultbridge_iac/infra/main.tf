###############################################################################
# infra/main.tf
#
# PURPOSE: Module orchestration. Wires the secrets and iam modules together
#          and passes their outputs to the root-level resources (ec2.tf, rds.tf).
#
# MODULE CALL ORDER (Terraform resolves this via dependency graph):
#   1. secrets  — generates credentials, creates Secrets Manager secret + KMS key
#   2. iam      — creates IAM roles scoped to the secret ARN from step 1
#   3. rds.tf   — uses credentials from secrets module, monitoring role from iam
#   4. ec2.tf   — uses instance profile from iam module
###############################################################################

# ── Secrets Module ────────────────────────────────────────────────────────────
# Provisions the KMS CMK used to encrypt the RDS-managed secret,
# CloudWatch Logs, and Performance Insights.
# RDS native rotation (manage_master_user_password = true) owns the secret.

module "secrets" {
  source = "./modules/secrets"

  project_name = var.project_name
  environment  = var.environment

  tags = local.common_tags
}

# ── IAM Module ────────────────────────────────────────────────────────────────
# Creates EC2 instance profile and RDS monitoring role.
# secret_arn comes from the RDS-managed secret (available after first apply).

module "iam" {
  source = "./modules/iam"

  project_name        = var.project_name
  environment         = var.environment
  secrets_kms_key_arn = module.secrets.kms_key_arn

  tags = local.common_tags
}

# ── Secrets Read Policy ───────────────────────────────────────────────────────
# Defined here (not in the iam module) to break the dependency cycle:
#   iam module → secret_arn → aws_db_instance → iam module (monitoring role)
# By placing it at root level, Terraform can resolve:
#   1. module.secrets (KMS key)
#   2. module.iam (roles, no secret dependency)
#   3. aws_db_instance (uses iam monitoring role)
#   4. aws_iam_policy.secrets_read + attachment (uses RDS secret ARN)

data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid    = "GetDBSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [try(aws_db_instance.postgres.master_user_secret[0].secret_arn, "*")]
  }

  statement {
    sid    = "DecryptSecretKMS"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = [module.secrets.kms_key_arn]
  }

  statement {
    sid    = "GetSecretArnSSMParam"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]
    resources = ["arn:aws:ssm:*:*:parameter/${var.project_name}/${var.environment}/db-secret-arn"]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.project_name}-secrets-read-${var.environment}"
  description = "Allows EC2 app server to read the RDS-managed DB secret"
  policy      = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role_policy_attachment" "ec2_secrets_read" {
  role       = module.iam.ec2_role_name
  policy_arn = aws_iam_policy.secrets_read.arn
}

###############################################################################
# infra/ssm.tf
#
# PURPOSE: Fetches database credentials from AWS SSM Parameter Store at
#          plan/apply time. Credentials are never stored in Terraform files,
#          tfvars, or state in plaintext.
#
# SETUP — store secrets once before running terraform apply:
#
#   aws ssm put-parameter \
#     --name "/vaultbridge/dev/db_username" \
#     --value "vaultbridge_admin" \
#     --type SecureString \
#     --region us-east-1
#
#   aws ssm put-parameter \
#     --name "/vaultbridge/dev/db_password" \
#     --value "your-strong-password-min-16-chars" \
#     --type SecureString \
#     --region us-east-1
#
# SecureString encrypts the value using AWS KMS. Only IAM identities with
# ssm:GetParameter + kms:Decrypt permissions can read it.
#
# The parameter path convention is: /<project>/<environment>/<secret_name>
# This makes it easy to manage secrets per environment (dev vs prod have
# separate parameters with separate access policies).
###############################################################################

data "aws_ssm_parameter" "db_username" {
  name            = "/${var.project_name}/${var.environment}/db_username"
  with_decryption = true
}

data "aws_ssm_parameter" "db_password" {
  name            = "/${var.project_name}/${var.environment}/db_password"
  with_decryption = true
}

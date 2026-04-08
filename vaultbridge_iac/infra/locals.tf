###############################################################################
# infra/locals.tf
#
# PURPOSE: Single source of truth for all resource naming and common values.
#          Every resource name in this workspace is derived from these locals.
#          Changing project_name or environment here propagates everywhere.
#
# CONVENTION: ${local.prefix}-<resource-type>-<qualifier>
#   e.g.  vaultbridge-dev-vpc
#         vaultbridge-dev-ec2-sg
#         vaultbridge-dev-rds
###############################################################################

locals {
  # ── Core identifiers ────────────────────────────────────────────────────────
  prefix = "${var.project_name}-${var.environment}"

  # ── Resource names ───────────────────────────────────────────────────────────
  names = {
    # Networking
    vpc            = "${local.prefix}-vpc"
    igw            = "${local.prefix}-igw"
    public_rt      = "${local.prefix}-public-rt"
    private_rt     = "${local.prefix}-private-rt"
    flow_log       = "${local.prefix}-vpc-flow-log"
    flow_log_group = "/aws/vpc/${local.prefix}-flow-logs"

    # Security Groups
    ec2_sg = "${local.prefix}-ec2-sg"
    rds_sg = "${local.prefix}-rds-sg"

    # Compute
    ec2         = "${local.prefix}-app-server"
    eip         = "${local.prefix}-eip"
    root_volume = "${local.prefix}-root-volume"

    # Database
    rds             = "${local.prefix}-db"
    db_subnet_group = "${local.prefix}-db-subnet-group"
    db_param_group  = "${local.prefix}-pg-params"

    # Secrets
    secret      = "${local.prefix}-db-secret"
    secrets_kms = "${local.prefix}-secrets-cmk"
  }

  # ── Common tags ──────────────────────────────────────────────────────────────
  # Merged with provider default_tags. Resource-specific tags add to these.
  common_tags = {
    Project     = "VaultBridge"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}

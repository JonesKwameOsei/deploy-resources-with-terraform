###############################################################################
# infra/rds.tf
#
# PURPOSE: Provisions the managed PostgreSQL database — RDS instance,
#          DB subnet group, and parameter group.
#
# CREDENTIALS: manage_master_user_password = true hands credential ownership
#              to RDS. AWS creates a Secrets Manager secret automatically,
#              encrypts it with the CMK, and rotates it on schedule.
#              No username/password ever appears in Terraform state or tfvars.
#
# SECURITY:
#   - Private subnets only — no internet route exists to reach this instance
#   - publicly_accessible = false — no public endpoint assigned by AWS
#   - storage_encrypted = true — AES-256 encryption at rest
#   - rds.force_ssl = 1 — all connections must use TLS
#   - Enhanced Monitoring — OS-level metrics via the dedicated IAM role
###############################################################################

# ── DB Subnet Group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name        = local.names.db_subnet_group
  description = "Private subnets for VaultBridge RDS instance"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = local.names.db_subnet_group
  }
}

# ── DB Parameter Group ────────────────────────────────────────────────────────

resource "aws_db_parameter_group" "postgres" {
  name        = local.names.db_param_group
  family      = "postgres16"
  description = "Custom parameter group for VaultBridge PostgreSQL 16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = local.names.db_param_group
  }
}

# ── RDS Instance ──────────────────────────────────────────────────────────────

resource "aws_db_instance" "postgres" {
  identifier = local.names.rds

  # Engine
  engine               = var.db_config.engine
  engine_version       = var.db_config.engine_version
  instance_class       = var.db_instance_class
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Storage
  allocated_storage     = var.db_config.allocated_storage
  max_allocated_storage = var.db_config.max_allocated_storage
  storage_type          = var.volume_type
  storage_encrypted     = true

  # Credentials — RDS native rotation. AWS generates the master username,
  # stores credentials in a Secrets Manager secret encrypted with the CMK,
  # and rotates the password automatically. Nothing lands in Terraform state.
  db_name                       = var.db_name
  manage_master_user_password   = true
  master_user_secret_kms_key_id = module.secrets.kms_key_arn

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backups
  backup_retention_period = var.db_selected_number
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Enhanced Monitoring — OS metrics every 60 seconds via dedicated IAM role
  monitoring_interval = 60
  monitoring_role_arn = module.iam.rds_monitoring_role_arn

  # Performance Insights — encrypted with the same CMK as the secret
  performance_insights_enabled          = true
  performance_insights_retention_period = var.db_selected_number
  performance_insights_kms_key_id       = module.secrets.kms_key_arn

  # IAM database authentication — allows IAM roles/users to authenticate
  # to the DB instead of a static password. Adds a second auth layer.
  iam_database_authentication_enabled = true

  #tfsec:ignore:aws-rds-enable-deletion-protection
  # Deletion protection is intentionally disabled in dev so the environment
  # can be torn down freely. Set to true in staging/prod terraform.tfvars.
  deletion_protection = false

  # Dev: skip final snapshot for easy teardown.
  # Production: set skip_final_snapshot = false
  skip_final_snapshot       = true
  final_snapshot_identifier = "${local.names.rds}-final-snapshot"

  tags = {
    Name = local.names.rds
    Role = "database"
  }

  # Ensure IAM role exists before RDS tries to use it for monitoring
  depends_on = [module.iam]
}

###############################################################################
# infra/rds.tf
#
# PURPOSE: Provisions the managed PostgreSQL database — RDS instance,
#          DB subnet group (required for VPC placement), and parameter group.
#
# SECURITY: The RDS instance is placed in private subnets with no internet
#           route. publicly_accessible = false ensures AWS does not assign
#           a public endpoint. The only path in is through the EC2 security
#           group reference in security_groups.tf.
###############################################################################

# ── DB Subnet Group ───────────────────────────────────────────────────────────
# Tells RDS which subnets it may place the instance in.
# Requires subnets in at least two AZs (AWS requirement for Multi-AZ readiness).

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group-${var.environment}"
  description = "Private subnets for VaultBridge RDS instance"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group-${var.environment}"
  }
}

# ── DB Parameter Group ────────────────────────────────────────────────────────
# Allows customisation of PostgreSQL engine parameters without replacing the
# instance. Using a custom group (rather than default) is best practice because
# it makes parameter changes visible in Terraform diffs.

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-pg-params-${var.environment}"
  family      = "postgres16"
  description = "Custom parameter group for VaultBridge PostgreSQL 16"

  # Force SSL connections — all data in transit must be encrypted.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-pg-params-${var.environment}"
  }
}

# ── RDS Instance ──────────────────────────────────────────────────────────────

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-db-${var.environment}"

  # Engine
  engine               = "postgres"
  engine_version       = "16"
  instance_class       = var.db_instance_class
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100 # Auto-scaling ceiling
  storage_type          = "gp3"
  storage_encrypted     = true # Encrypt data at rest

  # Credentials — fetched from SSM Parameter Store at apply time.
  # Never stored in tfvars or passed as variables.
  db_name  = var.db_name
  username = data.aws_ssm_parameter.db_username.value
  password = data.aws_ssm_parameter.db_password.value

  # Network — private subnets, no public endpoint
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backups — 7-day retention window
  backup_retention_period = 7
  backup_window           = "03:00-04:00" # UTC — low-traffic window
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Deletion protection — prevents accidental terraform destroy in production.
  # Set to false in dev if you need to tear down freely.
  deletion_protection = false

  # Skip final snapshot in dev. Set to true and provide a snapshot ID in prod.
  skip_final_snapshot       = true
  final_snapshot_identifier = "${var.project_name}-db-final-${var.environment}"

  # Performance Insights — free tier, useful for query analysis
  performance_insights_enabled = true

  tags = {
    Name = "${var.project_name}-db-${var.environment}"
    Role = "database"
  }
}

###############################################################################
# modules/iam/main.tf
#
# PURPOSE: Least-privilege IAM roles for EC2 and RDS to retrieve credentials
#          from Secrets Manager at runtime.
#
# ROLES CREATED:
#   1. ec2_secrets_role  — attached to the EC2 instance profile. Allows the
#      application process to call GetSecretValue on the DB secret and
#      Decrypt via KMS. Also includes SSM Session Manager permissions so
#      operators can shell in without opening port 22.
#
#   2. rds_monitoring_role — required by RDS Enhanced Monitoring. Allows
#      RDS to publish OS-level metrics to CloudWatch Logs.
#
# PRINCIPLE: Every permission is scoped to the specific secret ARN and KMS
#            key ARN. No wildcard resources on sensitive actions.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ── EC2 IAM Role ──────────────────────────────────────────────────────────────

resource "aws_iam_role" "ec2_secrets" {
  name               = "${var.project_name}-ec2-secrets-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "Allows VaultBridge EC2 app server to retrieve DB credentials from Secrets Manager"

  tags = merge(var.tags, {
    Name = "${var.project_name}-ec2-secrets-role-${var.environment}"
  })
}

# ── Secrets Manager Read Policy ───────────────────────────────────────────────
# NOTE: This policy is intentionally defined at the root level (main.tf) rather
# than inside this module. The secret ARN comes from the RDS-managed secret
# (aws_db_instance.postgres.master_user_secret[0].secret_arn), which creates a
# dependency cycle if wired through this module.
# See infra/main.tf for aws_iam_policy.secrets_read and its attachment.

# ── SSM Session Manager Policy ────────────────────────────────────────────────
# Allows operators to open a shell session via AWS Systems Manager without
# needing SSH or an open port 22. Production best practice.

resource "aws_iam_role_policy_attachment" "ec2_ssm_session" {
  role       = aws_iam_role.ec2_secrets.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ── CloudWatch Agent Policy ───────────────────────────────────────────────────
# Allows the CloudWatch agent on EC2 to publish application and system logs.

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_secrets.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ── EC2 Instance Profile ──────────────────────────────────────────────────────
# The instance profile is the container that attaches an IAM role to an EC2
# instance. You reference the profile name in aws_instance, not the role name.

resource "aws_iam_instance_profile" "ec2_secrets" {
  name = "${var.project_name}-ec2-instance-profile-${var.environment}"
  role = aws_iam_role.ec2_secrets.name

  tags = merge(var.tags, {
    Name = "${var.project_name}-ec2-instance-profile-${var.environment}"
  })
}

# ── RDS Enhanced Monitoring Role ──────────────────────────────────────────────
# RDS Enhanced Monitoring requires a dedicated IAM role to publish OS-level
# metrics (CPU steal, memory, disk I/O) to CloudWatch Logs every 60 seconds.

data "aws_iam_policy_document" "rds_monitoring_assume_role" {
  statement {
    sid     = "RDSMonitoringAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.project_name}-rds-monitoring-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role.json
  description        = "Allows RDS Enhanced Monitoring to publish metrics to CloudWatch"

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-monitoring-role-${var.environment}"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── VPC Flow Logs Role ────────────────────────────────────────────────────────
# VPC Flow Logs requires a dedicated IAM role to publish network traffic logs
# to CloudWatch Logs. Without this, tfsec aws-ec2-require-vpc-flow-logs fails.

data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    sid     = "VPCFlowLogsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name               = "${var.project_name}-vpc-flow-logs-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
  description        = "Allows VPC Flow Logs to publish to CloudWatch Logs"

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc-flow-logs-role-${var.environment}"
  })
}

data "aws_iam_policy_document" "flow_logs_write" {
  # Scope all actions to the specific log group and its log streams.
  # logs:CreateLogGroup requires the log group ARN itself.
  # logs:CreateLogStream / PutLogEvents / Describe* require the log stream ARN
  # which is a child of the log group — expressed as log_group_arn:*.

  statement {
    sid    = "CreateLogGroup"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DescribeLogGroups",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/${var.project_name}-${var.environment}-flow-logs",
    ]
  }

  statement {
    sid    = "WriteLogStreams"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/${var.project_name}-${var.environment}-flow-logs:*",
    ]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name   = "${var.project_name}-vpc-flow-logs-policy-${var.environment}"
  role   = aws_iam_role.vpc_flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}

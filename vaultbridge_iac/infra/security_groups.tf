###############################################################################
# infra/security_groups.tf
#
# PURPOSE: Defines firewall rules for EC2 and RDS following least-privilege.
#
# PRINCIPLE: Only allow what is explicitly required. Deny everything else.
#
# EC2 Security Group:
#   Inbound  — SSH from your IP only, HTTP/HTTPS from anywhere
#   Outbound — all (EC2 needs to pull packages, call APIs, etc.)
#
# RDS Security Group:
#   Inbound  — PostgreSQL (5432) from EC2 security group ONLY
#   Outbound — none (database should never initiate outbound connections)
###############################################################################

# ── EC2 Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg-${var.environment}"
  description = "Security group for the VaultBridge application server"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-ec2-sg-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# SSH — restricted to a single known IP. Never 0.0.0.0/0 in production.
resource "aws_vpc_security_group_ingress_rule" "ec2_ssh" {
  security_group_id = aws_security_group.ec2.id
  description       = "SSH access from operator IP only"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_ssh_cidr
}

# HTTP — application traffic
resource "aws_vpc_security_group_ingress_rule" "ec2_http" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP traffic"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# HTTPS — application traffic
resource "aws_vpc_security_group_ingress_rule" "ec2_https" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS traffic"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Outbound — allow all egress (package installs, API calls, etc.)
resource "aws_vpc_security_group_egress_rule" "ec2_all_egress" {
  security_group_id = aws_security_group.ec2.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── RDS Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg-${var.environment}"
  description = "Security group for the VaultBridge RDS PostgreSQL instance"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rds-sg-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# PostgreSQL — only from the EC2 security group. Not from a CIDR range.
# Using a security group reference means: "any resource in the EC2 SG can connect".
# This is more maintainable than hardcoding IPs.
resource "aws_vpc_security_group_ingress_rule" "rds_postgres_from_ec2" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL access from EC2 application server only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ec2.id
}

# No egress rule for RDS — databases should not initiate outbound connections.

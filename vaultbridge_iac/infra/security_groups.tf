###############################################################################
# infra/security_groups.tf
#
# PURPOSE: Least-privilege firewall rules for EC2 and RDS.
#
# EC2:  SSH (your IP only), HTTP/HTTPS (anywhere), all egress
# RDS:  PostgreSQL from EC2 security group only, no egress
###############################################################################

# ── EC2 Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "ec2" {
  name        = local.names.ec2_sg
  description = "Security group for the VaultBridge application server"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = local.names.ec2_sg
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_ssh" {
  security_group_id = aws_security_group.ec2.id
  description       = "SSH access from operator IP only"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_ssh_cidr
}

resource "aws_vpc_security_group_ingress_rule" "ec2_http" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP traffic"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ec2_https" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS traffic"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ec2_all_egress" {
  security_group_id = aws_security_group.ec2.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── RDS Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = local.names.rds_sg
  description = "Security group for the VaultBridge RDS PostgreSQL instance"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = local.names.rds_sg
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_postgres_from_ec2" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL access from EC2 application server only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ec2.id
}

# No egress rule for RDS — databases must not initiate outbound connections.

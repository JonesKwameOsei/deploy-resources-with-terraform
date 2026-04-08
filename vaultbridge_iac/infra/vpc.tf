###############################################################################
# infra/vpc.tf
#
# PURPOSE: Network foundation — VPC, public/private subnets, IGW, route tables.
#
# ARCHITECTURE:
#   Public subnets  → route to Internet Gateway → EC2 lives here
#   Private subnets → NO internet route          → RDS lives here
#
# The private subnets have no IGW route. This is an architectural constraint —
# no security group misconfiguration can expose the database to the internet.
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.names.vpc
  }
}

# ── Public Subnets ────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.prefix}-public-subnet-${count.index + 1}"
    Tier = "public"
  }
}

# ── Private Subnets ───────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.prefix}-private-subnet-${count.index + 1}"
    Tier = "private"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = local.names.igw
  }
}

# ── Public Route Table ────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = local.names.public_rt
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table ───────────────────────────────────────────────────────
# No internet route — architectural guarantee that RDS cannot be reached
# from the internet regardless of security group configuration.

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = local.names.private_rt
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── VPC Flow Logs ─────────────────────────────────────────────────────────────
# Captures metadata about all IP traffic in/out of the VPC — source IP,
# destination IP, port, protocol, and accept/reject decision. Essential for
# incident investigation and security auditing.
#
# Logs are published to CloudWatch Logs. The IAM role that grants VPC the
# permission to write is managed in modules/iam.

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = local.names.flow_log_group
  retention_in_days = 30
  kms_key_id        = module.secrets.kms_key_arn

  tags = {
    Name = local.names.flow_log_group
  }
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL" # Capture ACCEPT, REJECT, and all traffic
  iam_role_arn    = module.iam.vpc_flow_logs_role_arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    Name = local.names.flow_log
  }
}

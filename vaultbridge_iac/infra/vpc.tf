###############################################################################
# infra/vpc.tf
#
# PURPOSE: Defines the network foundation — VPC, public and private subnets,
#          internet gateway, and route tables.
#
# ARCHITECTURE:
#   Public subnets  → have a route to the Internet Gateway → EC2 lives here
#   Private subnets → NO route to the internet             → RDS lives here
#
# This architectural separation (not just a security group rule) makes it
# structurally impossible for the database to be reached from the internet.
###############################################################################

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # Required for RDS endpoint resolution

  tags = {
    Name = "${var.project_name}-vpc-${var.environment}"
  }
}

# ── Public Subnets ────────────────────────────────────────────────────────────
# Spread across two AZs for resilience. EC2 and the load balancer (future) live here.

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false # We use an Elastic IP instead; avoid auto-assign

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}-${var.environment}"
    Tier = "public"
  }
}

# ── Private Subnets ───────────────────────────────────────────────────────────
# No internet route. RDS subnet group requires subnets in at least two AZs.

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}-${var.environment}"
    Tier = "private"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
# Attaches the VPC to the internet. Only public subnets route through this.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw-${var.environment}"
  }
}

# ── Public Route Table ────────────────────────────────────────────────────────
# Routes all non-local traffic (0.0.0.0/0) to the internet gateway.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt-${var.environment}"
  }
}

# Associate each public subnet with the public route table.
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table ───────────────────────────────────────────────────────
# No internet route. Local VPC traffic only. This is the architectural guarantee
# that the database cannot be reached from the internet.

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt-${var.environment}"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

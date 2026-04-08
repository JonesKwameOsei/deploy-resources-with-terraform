###############################################################################
# infra/variables.tf
#
# PURPOSE: Declares all input variables. No default values for sensitive or
#          environment-specific settings — those live in terraform.tfvars
#          (which is gitignored).
#
# RULE: This file declares the shape and documentation of variables.
#       Actual values go in terraform.tfvars. Never the other way around.
###############################################################################

# ── General ──────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment. Controls naming and tagging. Valid: dev, staging, prod."
  type        = string
  default = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Short project identifier used as a prefix in all resource names."
  type        = string
  default     = "vaultbridge"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (one per AZ). RDS lives here."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "Two AZs to spread subnets across for high availability."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# ── Compute ───────────────────────────────────────────────────────────────────

variable "ec2_instance_type" {
  description = "EC2 instance type for the application server."
  type        = string
  default     = "t3.micro"
}

variable "ec2_ami_id" {
  description = "AMI ID for the EC2 instance. Use the latest Amazon Linux 2023 AMI for your region."
  type        = string
  # No default — must be explicitly set per region in terraform.tfvars
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access. Must already exist in AWS."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block permitted to SSH into the EC2 instance. Use your IP, not 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR block (e.g. 203.0.113.5/32)."
  }
}

# ── Database ──────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the initial database to create."
  type        = string
  default     = "vaultbridge"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB."
  type        = number
  default     = 20
}

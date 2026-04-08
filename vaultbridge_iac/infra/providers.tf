###############################################################################
# infra/providers.tf
#
# PURPOSE: Declares required Terraform and provider versions, and configures
#          the AWS provider with a region and default resource tags.
#
# WHY PIN VERSIONS: Without version constraints, terraform init will pull the
# latest provider, which may introduce breaking changes. Pinning to ~> 5.0
# allows patch updates (5.0.1, 5.1.0) but blocks major version jumps.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Default tags are applied to every resource created by this provider.
  # This satisfies audit requirements without repeating tags on every resource.
  default_tags {
    tags = {
      Project     = "VaultBridge"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "devops-team"
    }
  }
}

###############################################################################
# infra/providers.tf
#
# PURPOSE: Declares required Terraform and provider versions.
#
# VERSION PINNING: ~> 5.0 allows 5.x.x patch/minor updates but blocks 6.0.
# The random provider is required by the secrets module for credential
# generation.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Default tags applied to every resource. Defined in locals.tf.
  default_tags {
    tags = local.common_tags
  }
}

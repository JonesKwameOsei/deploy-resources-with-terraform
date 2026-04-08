###############################################################################
# infra/ec2.tf
#
# PURPOSE: Provisions the application server — EC2 instance, Elastic IP.
#
# IAM INSTANCE PROFILE: The EC2 instance is assigned the instance profile
#   from the iam module. This grants the application process permission to
#   call Secrets Manager GetSecretValue at runtime — no credentials on disk.
#
# SSM SESSION MANAGER: Port 22 / SSH is the only inbound rule on the SG.
#   For production, consider removing SSH entirely and using SSM Session
#   Manager exclusively (the IAM role already includes the managed policy).
#
# KEY PAIR: References an existing key pair by name. To create one:
#   ssh-keygen -t ed25519 -C "vaultbridge-dev" -f ~/.ssh/vaultbridge_dev
#   aws ec2 import-key-pair --key-name vaultbridge-dev \
#     --public-key-material fileb://~/.ssh/vaultbridge_dev.pub
###############################################################################

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amiID.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_pair_name

  # IAM instance profile — grants the app permission to call Secrets Manager
  iam_instance_profile = module.iam.ec2_instance_profile_name

  # user_data — runs once at first boot as root (cloud-init).
  # secret_arn is intentionally NOT baked into user_data — it causes hash
  # drift when master_user_secret is populated mid-apply. Instead, the ARN
  # is stored in an SSM Parameter (see aws_ssm_parameter.db_secret_arn below)
  # and db-connect.sh reads it from SSM at runtime.
  user_data = templatefile("${path.module}/db_setup.sh", {
    aws_region = var.aws_region
    db_host    = split(":", aws_db_instance.postgres.endpoint)[0]
    db_name    = var.db_name
    db_port    = 5432
    ssm_secret_arn_param = "/${var.project_name}/${var.environment}/db-secret-arn"
  })

  # Replace the instance if user_data changes (new script = new bootstrap)
  user_data_replace_on_change = true

  # Disable auto-assigned public IP — Elastic IP is used instead
  associate_public_ip_address = false

  root_block_device {
    volume_type           = var.volume_type
    volume_size           = var.volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = local.names.root_volume
    }
  }

  # IMDSv2 — token-based metadata access prevents SSRF credential theft
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring = true

  tags = {
    Name = local.names.ec2
    Role = "application"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# ── Elastic IP ────────────────────────────────────────────────────────────────

resource "aws_eip" "app_server" {
  domain   = "vpc"
  instance = aws_instance.app_server.id

  tags = {
    Name = local.names.eip
  }

  depends_on = [aws_internet_gateway.main]
}

# ── SSM Parameter — DB Secret ARN ─────────────────────────────────────────────
# Stores the RDS-managed secret ARN so db-connect.sh can read it at runtime
# without baking it into user_data (which causes hash drift mid-apply).
# The EC2 instance role already has ssm:GetParameter via AmazonSSMManagedInstanceCore.

resource "aws_ssm_parameter" "db_secret_arn" {
  name  = "/${var.project_name}/${var.environment}/db-secret-arn"
  type  = "SecureString"
  value = aws_db_instance.postgres.master_user_secret[0].secret_arn

  tags = {
    Name = "${var.project_name}-db-secret-arn-${var.environment}"
  }
}

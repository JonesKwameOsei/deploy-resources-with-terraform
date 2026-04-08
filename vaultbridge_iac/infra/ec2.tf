###############################################################################
# infra/ec2.tf
#
# PURPOSE: Provisions the application server — EC2 instance, key pair import,
#          and Elastic IP for a stable public address.
#
# KEY PAIR NOTE: We reference an existing key pair by name (var.key_pair_name).
# The private key must be stored securely by the operator and never committed
# to git. To create a key pair:
#   ssh-keygen -t ed25519 -C "vaultbridge-dev" -f ~/.ssh/vaultbridge_dev
#   aws ec2 import-key-pair --key-name vaultbridge-dev \
#     --public-key-material fileb://~/.ssh/vaultbridge_dev.pub
###############################################################################

# ── EC2 Instance ──────────────────────────────────────────────────────────────

resource "aws_instance" "app_server" {
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_pair_name

  # Disable public IP — we attach an Elastic IP instead for a stable address.
  associate_public_ip_address = false

  # Encrypt the root volume at rest.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-root-volume-${var.environment}"
    }
  }

  # IMDSv2 — require token-based metadata access to prevent SSRF attacks
  # that exploit the EC2 metadata endpoint.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforces IMDSv2
    http_put_response_hop_limit = 1
  }

  # Monitoring — enables detailed 1-minute CloudWatch metrics.
  monitoring = true

  tags = {
    Name = "${var.project_name}-app-server-${var.environment}"
    Role = "application"
  }

  lifecycle {
    # Prevent accidental replacement if the AMI ID is updated.
    # Remove this if you intentionally want to replace the instance.
    ignore_changes = [ami]
  }
}

# ── Elastic IP ────────────────────────────────────────────────────────────────
# A static public IP that persists across instance stop/start cycles.
# Without this, the public IP changes every time the instance restarts.

resource "aws_eip" "app_server" {
  domain   = "vpc"
  instance = aws_instance.app_server.id

  tags = {
    Name = "${var.project_name}-eip-${var.environment}"
  }

  depends_on = [aws_internet_gateway.main]
}

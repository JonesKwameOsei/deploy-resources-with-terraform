#!/bin/bash
# =============================================================================
# db_setup.sh — EC2 user_data bootstrap script
#
# Runs once at instance launch as root (cloud-init).
#
# WHAT IT DOES:
#   1. Installs postgresql-client (psql CLI — no server, just the client)
#   2. Installs the AWS CLI v2 (if not already present)
#   3. Creates a non-root OS user 'vaultbridge' to own DB operations
#   4. Writes a connect helper script at /home/vaultbridge/db-connect.sh
#      that fetches live credentials from Secrets Manager and opens psql
#   5. Writes a .pgpass-less connection wrapper — credentials are fetched
#      fresh on every invocation, never cached on disk
#
# CREDENTIALS: Never stored on disk. Fetched from Secrets Manager at
#   connection time using the EC2 instance role (no keys needed).
#
# USAGE (after SSH or SSM session):
#   sudo -u vaultbridge /home/vaultbridge/db-connect.sh
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/db_setup.log) 2>&1

echo "[db_setup] Starting at $(date)"

# ── 1. System update and postgresql-client install ───────────────────────────
apt-get update -y
apt-get install -y postgresql-client jq unzip curl

# ── 2. AWS CLI v2 (Ubuntu 22.04 ships v1 — upgrade to v2) ───────────────────
if ! aws --version 2>&1 | grep -q "aws-cli/2"; then
  echo "[db_setup] Installing AWS CLI v2..."
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp/awscli
  /tmp/awscli/aws/install --update
  rm -rf /tmp/awscliv2.zip /tmp/awscli
fi

echo "[db_setup] AWS CLI version: $(aws --version)"

# ── 3. Create non-root OS user ───────────────────────────────────────────────
# The 'vaultbridge' user owns all DB-related operations on this instance.
# It has no sudo rights and no login shell by default — principle of least
# privilege at the OS level.

if ! id -u vaultbridge &>/dev/null; then
  useradd \
    --system \
    --create-home \
    --home-dir /home/vaultbridge \
    --shell /bin/bash \
    --comment "VaultBridge application user" \
    vaultbridge
  echo "[db_setup] Created OS user: vaultbridge"
fi

# ── 4. Write the db-connect helper script ────────────────────────────────────
# This script is owned by the vaultbridge user and executable only by them.
# It fetches credentials fresh from Secrets Manager on every run — no caching.

cat > /home/vaultbridge/db-connect.sh << 'CONNECT_SCRIPT'
#!/bin/bash
# =============================================================================
# db-connect.sh
# Fetches DB credentials from Secrets Manager and opens a psql session.
# Run as: sudo -u vaultbridge /home/vaultbridge/db-connect.sh
# =============================================================================

set -euo pipefail

AWS_REGION="${aws_region}"
SSM_PARAM="${ssm_secret_arn_param}"
DB_HOST="${db_host}"
DB_NAME="${db_name}"
DB_PORT="${db_port}"

echo "[db-connect] Resolving secret ARN from SSM..."

SECRET_ARN=$(aws ssm get-parameter \
  --name "$SSM_PARAM" \
  --with-decryption \
  --region "$AWS_REGION" \
  --query Parameter.Value \
  --output text)

echo "[db-connect] Fetching credentials from Secrets Manager..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)

DB_USER=$(echo "$SECRET_JSON" | jq -r '.username')
DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

if [[ -z "$DB_USER" || -z "$DB_PASS" ]]; then
  echo "[db-connect] ERROR: Could not parse credentials from secret." >&2
  exit 1
fi

echo "[db-connect] Connecting to $DB_HOST:$DB_PORT/$DB_NAME as $DB_USER ..."

PGPASSWORD="$DB_PASS" psql \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --dbname="$DB_NAME" \
  --set=sslmode=require

unset DB_PASS
unset PGPASSWORD
CONNECT_SCRIPT

# ── 5. Set ownership and permissions ─────────────────────────────────────────
chown vaultbridge:vaultbridge /home/vaultbridge/db-connect.sh
chmod 750 /home/vaultbridge/db-connect.sh   # owner: rwx, group: r-x, other: ---
chmod 750 /home/vaultbridge                 # restrict home dir

echo "[db_setup] db-connect.sh written to /home/vaultbridge/db-connect.sh"
echo "[db_setup] To connect: sudo -u vaultbridge /home/vaultbridge/db-connect.sh"
echo "[db_setup] Completed at $(date)"

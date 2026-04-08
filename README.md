# VaultBridge Infrastructure as Code

Terraform project that provisions the VaultBridge AWS environment — VPC, EC2, and RDS — using a two-workspace pattern with remote state and S3-native locking.

---

## Project Structure

```
vaultbridge_iac/
├── bootstrap/          One-time setup. Creates the S3 bucket for remote state.
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── tags.tfvars
│   └── .gitignore
│
└── infra/              Main infrastructure workspace.
    ├── backend.tf      Remote state configuration (S3 + lockfile)
    ├── providers.tf    AWS provider and version constraints
    ├── variables.tf    Input variable declarations
    ├── vpc.tf          VPC, subnets, internet gateway, route tables
    ├── security_groups.tf  Firewall rules for EC2 and RDS
    ├── ec2.tf          EC2 instance, Elastic IP
    ├── rds.tf          RDS PostgreSQL, subnet group, parameter group
    ├── ssm.tf          SSM Parameter Store data sources for DB credentials
    ├── outputs.tf      Post-apply reference values
    ├── terraform.tfvars.example
    └── .gitignore
```

---

## Architecture

```
Internet
    │
    ▼
Internet Gateway
    │
Public Subnets  (us-east-1a, us-east-1b)  →  EC2 + Elastic IP
Private Subnets (us-east-1a, us-east-1b)  →  RDS PostgreSQL
```

Private subnets have no route to the internet gateway. The database cannot be reached from the internet regardless of security group configuration — this is an architectural constraint, not a policy.

---

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI v2, configured with credentials (`aws configure`)
- tfsec ([install guide](https://aquasecurity.github.io/tfsec))
- tflint ([install guide](https://github.com/terraform-linters/tflint))
- An EC2 key pair created in your target AWS region

---

## First-Time Setup

### 1. Store DB credentials in SSM Parameter Store

DB credentials are never stored in files. Store them once before deploying:

```bash
aws ssm put-parameter \
  --name "/vaultbridge/dev/db_username" \
  --value "vaultbridge_admin" \
  --type SecureString \
  --region us-east-1

aws ssm put-parameter \
  --name "/vaultbridge/dev/db_password" \
  --value "your-strong-password-min-16-chars" \
  --type SecureString \
  --region us-east-1
```

### 2. Deploy the bootstrap workspace

The bootstrap workspace runs once with local state to create the S3 bucket used by the main workspace.

```bash
cd vaultbridge_iac/bootstrap
terraform init
terraform plan -var-file="tags.tfvars"
terraform apply -var-file="tags.tfvars"
```

Note the `state_bucket_name` output. You will need it in the next step.

### 3. Configure the remote backend

Open `vaultbridge_iac/infra/backend.tf` and replace the bucket placeholder with the output from step 2:

```hcl
terraform {
  backend "s3" {
    bucket       = "vaultbridge-tfstate-dev-<your-suffix>"
    key          = "infra/terraform.tfstate"
    region       = "some-region"
    encrypt      = true
    use_lockfile = true
  }
}
```

### 4. Configure variable values

```bash
cd vaultbridge_iac/infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:
- `ec2_ami_id` — latest Amazon Linux 2023 AMI for your region
- `key_pair_name` — name of your existing EC2 key pair
- `allowed_ssh_cidr` — your IP address in CIDR notation (e.g. `203.0.113.5/32`)

---

## Static Analysis and Security Scanning

Two tools run before every `terraform plan`. Neither is optional.

### tfsec

tfsec scans Terraform code for security misconfigurations — things that would pass `terraform validate` but fail a security audit or expose infrastructure to attack.

What it catches in this project:
- Security groups open to `0.0.0.0/0` on sensitive ports
- Unencrypted EBS volumes or RDS storage
- S3 buckets with public access enabled
- EC2 instances without IMDSv2 enforced
- RDS instances with a public endpoint
- Missing encryption in transit (SSL not enforced)

Configuration: `vaultbridge_iac/.tfsec/config.yml`

```bash
# Scan the infra workspace
tfsec ./infra

# Human-readable output
tfsec ./infra --format lovely

# Only surface HIGH and CRITICAL findings
tfsec ./infra --minimum-severity HIGH

# JSON output for CI pipelines
tfsec ./infra --format json > tfsec-results.json
```

Any finding at MEDIUM severity or above fails the pipeline. Exclusions are documented with a written justification in `.tfsec/config.yml` — no rule is silenced without a reason on record.

---

### tflint

tflint catches correctness issues that tfsec does not cover. It validates Terraform code against the actual AWS API, not just HCL syntax.

What it catches in this project:
- Invalid EC2 instance types (`t3.mciro` passes `terraform validate`, fails tflint)
- Invalid RDS instance classes
- Deprecated resource types and arguments
- Variables declared without descriptions
- Unused variable declarations
- Missing `required_providers` entries

Configuration: `vaultbridge_iac/.tflint.hcl`

```bash
# Download plugins declared in .tflint.hcl (run once after cloning)
tflint --init

# Lint the infra workspace
tflint --chdir=infra

# Lint the bootstrap workspace
tflint --chdir=bootstrap

# Compact output for CI
tflint --chdir=infra --format compact
```

---

### How the two tools relate

| Tool | Catches | Does not catch |
|---|---|---|
| tfsec | Security misconfigurations | Invalid AWS resource values |
| tflint | Invalid AWS values, deprecated syntax | Runtime security issues |
| terraform validate | HCL syntax errors | Either of the above |

All three run in sequence before any plan is reviewed or applied.

---

## Deployment Workflow

Every infrastructure change follows this sequence without exception.

```bash
cd vaultbridge_iac/infra

# 1. Format
terraform fmt -recursive

# 2. Lint — catch invalid AWS values and deprecated syntax
tflint --chdir=.

# 3. Security scan — catch misconfigurations before they reach AWS
tfsec .

# 4. Validate
terraform validate

# 5. Plan — review every change before applying
terraform plan -out=tfplan

# 6. Apply the reviewed plan
terraform apply tfplan

# 7. Verify
terraform output
```

---

## State Management

| Concern | Implementation |
|---|---|
| Remote state storage | S3 bucket with versioning and AES256 encryption |
| Concurrent apply protection | S3-native locking via `use_lockfile = true` |
| State access | Any engineer with the correct IAM permissions can run plan/apply |

DynamoDB-based locking is not used. It is deprecated in recent Terraform versions and has been removed from this project in favour of S3-native locking.

---

## Security Controls

| Control | Detail |
|---|---|
| DB credentials | Stored in AWS SSM Parameter Store as `SecureString`, fetched at apply time |
| SSH access | Restricted to a single operator CIDR (`allowed_ssh_cidr`), never `0.0.0.0/0` |
| RDS network access | Security group reference from EC2 SG only — no public endpoint |
| EC2 metadata | IMDSv2 enforced (`http_tokens = required`) |
| Storage encryption | EBS root volume and RDS storage encrypted at rest |
| S3 state bucket | Public access blocked, versioning enabled, server-side encryption enabled |
| tfsec | Scans for security misconfigurations before every apply — fails on MEDIUM+ |
| tflint | Validates AWS resource values and catches deprecated syntax before every apply |

---

## Outputs

After `terraform apply`, retrieve values with:

```bash
terraform output              # all outputs
terraform output ec2_public_ip
terraform output rds_endpoint
terraform output ec2_ssh_command
```

---

## Environment Parity

The same codebase deploys to dev, staging, or prod by changing variable values. To deploy a staging environment, create a separate `terraform.tfvars` with `environment = "staging"` and store the corresponding SSM parameters under `/vaultbridge/staging/`.

---

## What is Not Included

This project covers foundational infrastructure. The following are out of scope and would be added for a production migration:

- NAT Gateway (required if private subnet resources need outbound internet access)
- Application Load Balancer
- Auto Scaling Group
- CloudWatch alarms and log groups
- IAM roles and instance profiles for EC2
- Route 53 DNS records
- ACM certificates

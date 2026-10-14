# rds module — shared MySQL 8.0 instance for the three database-backed
# services (customers, visits, vets — one petclinic database, see
# docs/database-init.md), plus the DB subnet group, utf8mb4 parameter group,
# and the Secrets Manager secret holding the master credentials.
#
# Network access control lives in the VPC module: the RDS security group
# allows 3306 from the EKS node SG only (technical-spec.md → Security Groups).
# This module receives that SG id as an input — it never creates wide-open rules.
#
# technical-spec.md → RDS Database, Secrets Management, Terraform Modules
# Stories: PETPLAT-22 (module), PETPLAT-23 (credentials in Secrets Manager)

locals {
  # Tags merged into every resource. Project/Environment/ManagedBy mirror the
  # provider default_tags; Component is the module-level classification
  # (technical-spec.md → Optional Tags). var.tags allows extra service tags.
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "database"
    },
    var.tags,
  )

  # Naming per technical-spec.md: petclinic-{env}-mysql for the instance,
  # petclinic/{env}/rds-credentials for the secret (forward-slash convention).
  db_identifier = "${var.project}-${var.environment}-mysql"
  secret_name   = "${var.project}/${var.environment}/rds-credentials"
}

# -----------------------------------------------------------------------------
# Credentials (PETPLAT-23) — generated, never hardcoded.
#
# NOTE: Terraform cannot keep the password out of state entirely (the
# aws_db_instance resource references it), so state itself must be protected:
# S3 + SSE + DynamoDB locking per technical-spec.md → Terraform State Backend.
# The values are marked sensitive so they never appear in plan/CLI output.
# -----------------------------------------------------------------------------

resource "random_password" "master" {
  length  = 16
  special = true

  # RDS MySQL rejects ", /, @ and space in the master password — restrict the
  # special-character set to characters RDS accepts.
  override_special = "!#%*()-_=+[]{}<>:?"

  # Guarantee complexity: at least one of each character class.
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

# Random suffix for the final snapshot name (review fix M-3): a static
# "-final" name fails with DBSnapshotAlreadyExists on a second
# destroy/restore cycle, which can strand the instance in "deleting".
resource "random_id" "final_snapshot" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "rds" {
  name        = local.secret_name
  description = "RDS master credentials for ${local.db_identifier} (${var.project}/${var.environment})"

  # 30-day recovery window protects prod against accidental deletion. The dev
  # environment sets 0 so `terraform destroy` can immediately re-create a
  # secret with the same name on the next session (otherwise the name stays
  # locked in "scheduled deletion" for 30 days).
  recovery_window_in_days = var.secret_recovery_window_in_days

  # Review fix I-1: never allow immediate, irreversible deletion in prod
  # (precondition instead of cross-variable validation, which needs TF >= 1.9).
  lifecycle {
    precondition {
      condition     = var.environment != "prod" || var.secret_recovery_window_in_days > 0
      error_message = "prod must keep a non-zero secret_recovery_window_in_days (0 deletes the secret immediately and irrecoverably)."
    }
  }

  tags = merge(local.tags, {
    Name = local.secret_name
  })
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  # Single JSON secret with username/password keys (PETPLAT-23) — consumed
  # later by the ExternalSecret in k8s/base/external-secrets/.
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
  })
}


# -----------------------------------------------------------------------------
# Networking — DB subnet group across the VPC public subnets (2 AZs). All
# resources run in public subnets (ADR-0001); access is restricted by the RDS
# security group, and publicly_accessible stays false so the instance is only
# reachable through the VPC network path.
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = local.db_identifier
  subnet_ids = var.subnet_ids

  description = "DB subnet group for ${local.db_identifier} (public subnets, 2 AZs)"

  tags = merge(local.tags, {
    Name = local.db_identifier
  })
}

# -----------------------------------------------------------------------------
# Parameter group — full Unicode support (technical-spec.md → Parameter Group).
# -----------------------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  name   = local.db_identifier
  family = "mysql${var.engine_version}"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # Enforce TLS for client connections (review fix M-2). MySQL Connector/J's
  # default sslMode=PREFERRED negotiates TLS transparently, so the Spring
  # services connect unchanged; this only rejects unencrypted clients.
  # Note: stricter than technical-spec.md's "SSL available (not enforced)".
  parameter {
    name  = "require_secure_transport"
    value = "1"
  }

  tags = merge(local.tags, {
    Name = local.db_identifier
  })
}

# -----------------------------------------------------------------------------
# DB instance — MySQL 8.0, single shared `petclinic` database (PETPLAT-22).
# Encryption at rest with the AWS-managed KMS key (technical-spec.md →
# Encryption Matrix). Multi-AZ / backup retention / final snapshot are all
# variable-driven per environment.
# -----------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier     = local.db_identifier
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage: 20 GB gp2 (free tier), autoscaling bounded by
  # max_allocated_storage, encrypted with the AWS default KMS key.
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  # Single shared database for customers/visits/vets (PETPLAT-24 —
  # docs/database-init.md). Master credentials: username from variable,
  # password from random_password (PETPLAT-23), stored in Secrets Manager.
  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.security_group_id]

  # Defense in depth: even though the RDS SG only admits the EKS node SG on
  # 3306, the instance must not get a public address (all-public design,
  # ADR-0001 — the SG is the perimeter).
  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  # Review fix L-2: export slow-query and error logs to CloudWatch Logs for
  # incident RCA. "general" is intentionally omitted — it is high-volume and
  # adds cost with little diagnostic value for this project.
  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]

  # Review fix I-2: make the AWS default explicit — minor engine patches are
  # applied automatically during the maintenance window (security patching
  # without operator action).
  auto_minor_version_upgrade = true

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.db_identifier}-final-${random_id.final_snapshot.hex}"

  deletion_protection = var.deletion_protection

  tags = merge(local.tags, {
    Name = local.db_identifier
  })
}

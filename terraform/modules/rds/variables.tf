# Input variables for the rds module (technical-spec.md → Terraform Modules,
# PETPLAT-22).

variable "project" {
  description = "Project name used for naming (petclinic-{env}-mysql) and tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group. Must span at least 2 availability zones (AWS requirement for DB subnet groups)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least 2 subnets in different availability zones."
  }
}

variable "security_group_id" {
  description = "RDS security group ID (from the VPC module — allows 3306 from the EKS node SG only)."
  type        = string

  validation {
    condition     = can(regex("^sg-", var.security_group_id))
    error_message = "security_group_id must be an AWS security group ID (sg-...)."
  }
}

variable "instance_class" {
  description = "RDS instance class. db.t4g.micro is free-tier eligible (ARM/Graviton)."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GB (MySQL minimum on gp2)."
  }
}

variable "max_allocated_storage" {
  description = "Upper limit for automatic storage autoscaling in GB. Must exceed allocated_storage — RDS disables autoscaling when both values are equal (PETPLAT-22 requires autoscaling enabled)."
  type        = number
  default     = 100

  validation {
    condition     = var.max_allocated_storage > 0
    error_message = "max_allocated_storage must be positive."
  }
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment. false for dev and prod (cost optimization for this learning project) — enable in real production."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Automated backup retention in days (7 for dev, 30 for prod)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days."
  }
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when the instance is destroyed. true for dev (fast teardown), false for prod."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection. false per technical-spec.md → RDS Database (students tear down after each session)."
  type        = bool
  default     = false
}

variable "master_username" {
  description = "Master username for the petclinic database (stored alongside the generated password in Secrets Manager)."
  type        = string
  default     = "petclinic"
}

variable "db_name" {
  description = "Name of the initial database schema created on the instance. All three domain services (customers, visits, vets) share this single database."
  type        = string
  default     = "petclinic"
}

variable "engine_version" {
  description = "MySQL engine version."
  type        = string
  default     = "8.0"
}

variable "backup_window" {
  description = "Daily UTC window for automated backups (HH:MM-HH:MM). Must not overlap the maintenance window."
  type        = string
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.backup_window))
    error_message = "backup_window must be in HH:MM-HH:MM format (e.g. 03:00-04:00)."
  }
}

variable "maintenance_window" {
  description = "Weekly UTC window for engine maintenance (ddd:HH:MM-ddd:HH:MM)."
  type        = string
  default     = "sun:04:00-sun:05:00"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must be in ddd:HH:MM-ddd:HH:MM format (e.g. sun:04:00-sun:05:00)."
  }
}

variable "secret_recovery_window_in_days" {
  description = "Recovery window for aws_secretsmanager_secret (0-30). 30 protects against accidental deletion; set 0 in dev only so terraform destroy can immediately re-create the secret with the same name on the next session."
  type        = number
  default     = 30

  validation {
    condition     = var.secret_recovery_window_in_days >= 0 && var.secret_recovery_window_in_days <= 30
    error_message = "secret_recovery_window_in_days must be between 0 and 30."
  }
}

variable "tags" {
  description = "Additional tags merged into all resources."
  type        = map(string)
  default     = {}
}

# Input variables for the vpc module (technical-spec.md → Terraform Modules).

variable "project" {
  description = "Project name used for naming and tagging."
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

variable "vpc_cidr" {
  description = "VPC CIDR block (dev: 10.0.0.0/16, prod: 10.1.0.0/16)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets, one per availability zone (exactly 2)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly 2 CIDRs (one per availability zone)."
  }
}

variable "availability_zones" {
  description = "Availability zones for the public subnets (exactly 2)."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "availability_zones must contain exactly 2 AZs."
  }
}

variable "tags" {
  description = "Additional tags merged into all resources."
  type        = map(string)
  default     = {}
}

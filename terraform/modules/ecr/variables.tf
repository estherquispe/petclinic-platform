# Input variables for the ecr module (PETPLAT-18/19).

variable "project" {
  description = "Project name used for the repository naming convention (petclinic-{env}/{service})."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod). Determines the petclinic-{env}/ repository namespace and the default tag mutability."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "service_names" {
  description = "Service names — one ECR repository is created per name (e.g. config-server, api-gateway)."
  type        = list(string)

  validation {
    condition     = length(var.service_names) > 0 && alltrue([for name in var.service_names : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))])
    error_message = "service_names must be a non-empty list of lowercase kebab-case names (e.g. config-server)."
  }
}

variable "image_tag_mutability" {
  description = "ECR image tag mutability: MUTABLE or IMMUTABLE. Leave null to derive from the environment (MUTABLE for dev, IMMUTABLE for prod)."
  type        = string
  default     = null

  validation {
    condition     = var.image_tag_mutability == null || contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE, or null to derive from the environment."
  }
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories even when they still contain images. true for dev (frequent teardown cycles, see technical-spec.md cost note), false for prod so images survive an accidental destroy."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged into every repository."
  type        = map(string)
  default     = {}
}


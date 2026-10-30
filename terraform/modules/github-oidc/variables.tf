# Input variables for the github-oidc module (PETPLAT-52).
#
# The GitHub repository value is derived from the application repo remote URL
# (git remote get-url origin), e.g.
#   https://github.com/estherquispe/spring-petclinic-microservices.git
# -> estherquispe/spring-petclinic-microservices
# The OIDC trust policy restricts the federated subject to this repo on main
# only — never the platform repo, never *.

variable "project" {
  description = "Project name used in resource names and tags (petclinic-{env}-{resource})."
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

variable "github_repository" {
  description = "Application repository in owner/repo form (derived from the app repo remote URL). The OIDC trust policy subject is restricted to repo:{github_repository}:ref:refs/heads/main."
  type        = string
  default     = "estherquispe/spring-petclinic-microservices"
}

variable "oidc_provider_url" {
  description = "GitHub Actions OIDC provider URL (audience issuer)."
  type        = string
  default     = "token.actions.githubusercontent.com"
}

variable "role_name" {
  description = "Name of the IAM role assumed by GitHub Actions via OIDC federation."
  type        = string
  default     = "petclinic-github-actions-role"
}

variable "repository_arns" {
  description = "ARNs of the ECR repositories the role may push images to (ecr:BatchCheckLayerAvailability, layer upload actions, ecr:PutImage). GetAuthorizationToken is account-scoped (Resource: *)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
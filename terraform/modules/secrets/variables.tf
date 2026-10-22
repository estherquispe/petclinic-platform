variable "project" {
  description = "Project name used for the secret naming convention (petclinic/{env}/...)."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod); used to scope the secret names."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "openai_api_key" {
  description = "OpenAI API key value for the GenAI service. Stored as the plaintext value of the petclinic/{env}/openai-api-key secret. Provide via -var or terraform.tfvars; never hardcode."
  type        = string
  sensitive   = true
}

variable "config_server_git_username" {
  description = "Optional Git username for the config-server Git backend. When set, a petclinic/{env}/config-server/git-username secret is created. Leave null to skip."
  type        = string
  default     = null
  sensitive   = true
}

variable "config_server_git_password" {
  description = "Optional Git password/token for the config-server Git backend. When set, a petclinic/{env}/config-server/git-password secret is created. Leave null to skip."
  type        = string
  default     = null
  sensitive   = true
}

variable "tags" {
  description = "Additional tags merged into the tags applied to every secret."
  type        = map(string)
  default     = {}
}


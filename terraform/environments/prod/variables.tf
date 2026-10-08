# Input variables for the prod environment root module.

variable "aws_region" {
  description = "AWS region where all resources are created."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "project" {
  description = "Project name used for naming convention and tagging."
  type        = string
  default     = "petclinic"
}

variable "eks_admin_principal_arns" {
  description = "IAM principals granted EKS cluster admin via access entries. Leave empty to use the deploying caller. If deploying with an assumed-role/STS session, set this to the IAM role or user ARN instead (see docs/runbooks/eks-access-and-addons.md)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.eks_admin_principal_arns : !startswith(arn, "arn:aws:sts::")])
    error_message = "eks_admin_principal_arns must be IAM user/role ARNs (arn:aws:iam::...), not STS session ARNs (arn:aws:sts::...:assumed-role/...)."
  }
}

variable "api_server_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API server endpoint. RESTRICT THIS to your deployer/CI network (e.g. \"203.0.113.10/32\") — 0.0.0.0/0 leaves the API open to the internet (see docs/runbooks/eks-access-and-addons.md)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

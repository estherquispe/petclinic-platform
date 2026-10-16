# Input variables for the dev environment root module.

variable "aws_region" {
  description = "AWS region where all resources are created."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string
  default     = "dev"

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

variable "domain_name" {
  description = "Apex domain of the existing Route 53 public hosted zone used for the ACM certificate and the petclinic-dev.{domain} DNS record (PETPLAT-28/32). The zone must already exist — it is looked up with a data source, not created."
  type        = string
  default     = "estherquispe.click"
}

variable "alb_dns_name" {
  description = "DNS name of the internet-facing ALB created by the AWS Load Balancer Controller from k8s/base/ingress/ingress.yaml (PETPLAT-31). Leave null until the Ingress has been applied and the ALB exists, then set it in terraform.tfvars together with alb_hosted_zone_id: kubectl -n petclinic-dev get ingress api-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  type        = string
  default     = null
}

variable "alb_hosted_zone_id" {
  description = "Canonical hosted zone ID of that ALB (PETPLAT-31) — e.g. Z35SXDOTRQ7X7K (no /hostedzone/ prefix): aws elbv2 describe-load-balancers --names <alb-name> --query 'LoadBalancers[0].CanonicalHostedZoneId'. Leave null together with alb_dns_name until the Ingress has been applied."
  type        = string
  default     = null
}

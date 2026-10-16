# Input variables for the dns module (PETPLAT-28, PETPLAT-31).
# technical-spec.md → DNS and Ingress, Terraform Modules (Module: dns).

variable "domain_name" {
  description = "Apex domain of the EXISTING Route 53 public hosted zone to use (e.g. estherquispe.click). The zone is looked up with a data source, never created — Route 53 already created it when the domain was registered, and creating a second one would put the ACM validation records in an un-delegated zone so the certificate would never be issued."
  type        = string

  validation {
    condition     = trimspace(var.domain_name) != "" && !endswith(trimspace(var.domain_name), ".")
    error_message = "domain_name must be a non-empty domain without a trailing dot (e.g. estherquispe.click)."
  }
}

variable "record_name" {
  description = "Relative DNS name of the application alias A record pointing to the ALB (e.g. \"petclinic-dev\" creates petclinic-dev.{domain_name}). Leave null to defer the record until the ALB exists (PETPLAT-31)."
  type        = string
  default     = null

  validation {
    condition     = var.record_name == null || (trimspace(var.record_name) != "" && !endswith(trimspace(var.record_name), "."))
    error_message = "record_name must be null or a non-empty relative DNS name without a trailing dot (e.g. petclinic-dev)."
  }
}

variable "alb_dns_name" {
  description = "DNS name of the internet-facing ALB created by the AWS Load Balancer Controller from k8s/base/ingress/ingress.yaml (e.g. k8s-petclinic-ingress-....elb.amazonaws.com). Leave null until the Ingress has been applied. Must be set together with alb_hosted_zone_id."
  type        = string
  default     = null

  validation {
    condition     = var.alb_dns_name == null || endswith(var.alb_dns_name, ".elb.amazonaws.com")
    error_message = "alb_dns_name must be an ELB DNS name ending in .elb.amazonaws.com (get it from the Ingress status: kubectl -n petclinic-dev get ingress api-gateway)."
  }
}

variable "alb_hosted_zone_id" {
  description = "Canonical hosted zone ID of that ALB (e.g. Z35SXDOTRQ7X7K — the value shown in the alias zone_id, not the /hostedzone/ form). Leave null until the Ingress has been applied. Must be set together with alb_dns_name."
  type        = string
  default     = null

  validation {
    condition     = var.alb_hosted_zone_id == null || (startswith(var.alb_hosted_zone_id, "Z") && !can(regex("/", var.alb_hosted_zone_id)))
    error_message = "alb_hosted_zone_id must be the bare canonical zone ID (e.g. Z35SXDOTRQ7X7K) without the /hostedzone/ prefix."
  }
}

variable "tags" {
  description = "Additional tags merged into taggable resources (required Project/Environment/ManagedBy tags come from the provider default_tags)."
  type        = map(string)
  default     = {}
}

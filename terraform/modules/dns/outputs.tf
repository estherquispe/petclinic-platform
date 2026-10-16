# Outputs for the dns module (PETPLAT-28/31) — consumed by the environment
# roots and, via the certificate_arn, by the ALB Ingress manifest.

output "zone_id" {
  description = "ID of the existing Route 53 public hosted zone for domain_name."
  value       = data.aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "NS delegation records of the hosted zone (already delegated — the zone was created with the registered domain)."
  value       = data.aws_route53_zone.this.name_servers
}

output "zone_name_servers" {
  description = "Same as name_servers — output name required by the PETPLAT-28 acceptance criteria."
  value       = data.aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "ARN of the DNS-validated wildcard ACM certificate (*.{domain}) for the ALB HTTPS listener. Depends on aws_acm_certificate_validation, so consumers only see it once the certificate is ISSUED."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "record_fqdn" {
  description = "FQDN of the application alias A record pointing to the ALB (null while alb_dns_name/alb_hosted_zone_id are unset — PETPLAT-31)."
  value       = try(aws_route53_record.app[0].fqdn, null)
}

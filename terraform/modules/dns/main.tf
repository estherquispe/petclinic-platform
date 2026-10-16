# dns module — Route 53 hosted zone lookup (data source) + ACM certificate with
# DNS validation + optional alias A record pointing at the ALB.
#
# Stories: PETPLAT-28 (zone lookup, certificate, validation records),
#          PETPLAT-31 (alias record → ALB)
# technical-spec.md → DNS and Ingress, Terraform Modules (Module: dns)
#
# The hosted zone is looked up with a DATA SOURCE, never created as a resource:
# Route 53 creates a hosted zone automatically when a domain is registered, and
# a second zone created by Terraform would receive the ACM validation records in
# a zone that is not delegated — the certificate would never be issued.

data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

# Wildcard certificate for *.{domain} (technical-spec.md → ACM Certificate),
# validated with DNS, in the same region as the ALB (us-east-1).
resource "aws_acm_certificate" "this" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  tags = merge(var.tags, {
    # ACM tag values allow only [\p{L}\p{Z}\p{N}_.:/=+\-@]* (no "*"), so the
    # wildcard is spelled "wildcard" here — RequestCertificate rejects a
    # literal "*." in tag values with a ValidationException.
    Name = "wildcard.${var.domain_name}" # recognizable in the ACM console
  })

  # Issue the replacement before destroying the current certificate so the ALB
  # HTTPS listener never loses a certificate during rotation.
  lifecycle {
    create_before_destroy = true
  }
}

# ACM DNS validation CNAMEs — created in the EXISTING hosted zone looked up above.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    # Keyed by resource_record_name (collision-proof if SANs are ever added —
    # several SANs can share one domain_name but never one record name).
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.resource_record_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  # The validation record is re-created whenever the certificate rotates.
  allow_overwrite = true
}

# Block until ACM reports the certificate ISSUED (PETPLAT-28 acceptance
# criteria: certificate validation completed).
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "15m"
  }
}

# Guard rails for the conditional alias record inputs (PETPLAT-31): the two ALB
# values always travel together, and the record needs a name. check blocks emit
# warnings instead of hard failures, so a plan with the record deferred still
# succeeds.
check "alb_record_inputs" {
  assert {
    condition     = (var.alb_dns_name == null) == (var.alb_hosted_zone_id == null)
    error_message = "alb_dns_name and alb_hosted_zone_id must be set together (or both left null) — the PETPLAT-31 alias record needs both."
  }

  assert {
    condition     = var.alb_dns_name == null || var.record_name != null
    error_message = "record_name must be set whenever alb_dns_name/alb_hosted_zone_id are set — the alias record needs a name (e.g. petclinic-dev)."
  }
}

# Application alias A record → ALB (PETPLAT-31): petclinic-dev.{domain} (A,
# alias) → internet-facing ALB. Created only when the ALB endpoint is known —
# the ALB itself is provisioned by the AWS Load Balancer Controller watching
# k8s/base/ingress/ingress.yaml, i.e. outside Terraform, so its DNS name and
# hosted zone ID are passed in (dev terraform.tfvars) after the Ingress has
# been applied. HTTP→HTTPS redirect is handled by the controller
# (alb.ingress.kubernetes.io/ssl-redirect), not by this record.
resource "aws_route53_record" "app" {
  count = var.record_name != null && var.alb_dns_name != null && var.alb_hosted_zone_id != null ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.record_name # relative name → petclinic-dev.{domain}
  type    = "A"

  alias {
    name    = var.alb_dns_name
    zone_id = var.alb_hosted_zone_id
    # With evaluate_target_health the record stops answering while the ALB has
    # no healthy targets (e.g. all pods down) — good traffic steering, but keep
    # it in mind when debugging an empty DNS answer.
    evaluate_target_health = true
  }
}

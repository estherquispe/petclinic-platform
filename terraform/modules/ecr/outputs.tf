# Outputs for the ecr module (PETPLAT-18) — consumed by the CI pipeline and
# Kubernetes image references.

output "repository_urls" {
  description = "Map of service_name → ECR repository URL (e.g. config-server → {account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/config-server)."
  value       = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service_name → ECR repository ARN."
  value       = { for name, repo in aws_ecr_repository.service : name => repo.arn }
}

output "image_tag_mutability" {
  description = "Effective image tag mutability for this environment (MUTABLE or IMMUTABLE)."
  value       = local.image_tag_mutability
}


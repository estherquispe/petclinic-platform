# Outputs for the github-oidc module (PETPLAT-52) — consumed by CI pipeline
# configuration (AWS_ROLE_ARN secret) and environment root modules.

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_provider_url" {
  description = "URL of the GitHub Actions OIDC provider (with scheme)."
  value       = local.provider_url
}

output "role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions (AWS_ROLE_ARN secret)."
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  value       = aws_iam_role.github_actions.name
}

output "trust_subject" {
  description = "Federated subject restricted in the trust policy (repo:owner/repo:ref:refs/heads/main)."
  value       = local.sub
}
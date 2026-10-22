output "openai_secret_arn" {
  description = "ARN of the petclinic/{env}/openai-api-key secret."
  value       = aws_secretsmanager_secret.openai_api_key.arn
  sensitive   = true
}

output "config_server_git_username_secret_arn" {
  description = "ARN of the petclinic/{env}/config-server/git-username secret, or null when not configured."
  value       = var.config_server_git_username != null && var.config_server_git_username != "" ? aws_secretsmanager_secret.config_server_git_username[0].arn : null
  sensitive   = true
}

output "config_server_git_password_secret_arn" {
  description = "ARN of the petclinic/{env}/config-server/git-password secret, or null when not configured."
  value       = var.config_server_git_password != null && var.config_server_git_password != "" ? aws_secretsmanager_secret.config_server_git_password[0].arn : null
  sensitive   = true
}


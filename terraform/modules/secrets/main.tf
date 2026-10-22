# secrets module — AWS Secrets Manager secrets (non-RDS application secrets)
#
# Implements PETPLAT-33. Creates petclinic/{env}/openai-api-key (required)
# plus optional petclinic/{env}/config-server/git-username and
# petclinic/{env}/config-server/git-password. RDS credentials are owned by
# the rds module (PETPLAT-23) and are intentionally not created here.
#
# The OpenAI API key is accepted as a sensitive variable and never hardcoded.

# petclinic/{env}/openai-api-key — required, non-RDS secret.
resource "aws_secretsmanager_secret" "openai_api_key" {
  name        = "${var.project}/${var.environment}/openai-api-key"
  description = "OpenAI API key for the ${var.environment} Petclinic deployment."

  tags = merge(local.common_tags, var.tags)
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key
}

# petclinic/{env}/config-server/git-username — optional.
resource "aws_secretsmanager_secret" "config_server_git_username" {
  count = var.config_server_git_username != null && var.config_server_git_username != "" ? 1 : 0

  name        = "${var.project}/${var.environment}/config-server/git-username"
  description = "Git username for the config-server Git backend."

  tags = merge(local.common_tags, var.tags)
}

resource "aws_secretsmanager_secret_version" "config_server_git_username" {
  count = var.config_server_git_username != null && var.config_server_git_username != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.config_server_git_username[0].id
  secret_string = var.config_server_git_username
}

# petclinic/{env}/config-server/git-password — optional.
resource "aws_secretsmanager_secret" "config_server_git_password" {
  count = var.config_server_git_password != null && var.config_server_git_password != "" ? 1 : 0

  name        = "${var.project}/${var.environment}/config-server/git-password"
  description = "Git password/token for the config-server Git backend."

  tags = merge(local.common_tags, var.tags)
}

resource "aws_secretsmanager_secret_version" "config_server_git_password" {
  count = var.config_server_git_password != null && var.config_server_git_password != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.config_server_git_password[0].id
  secret_string = var.config_server_git_password
}

 locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }
 }


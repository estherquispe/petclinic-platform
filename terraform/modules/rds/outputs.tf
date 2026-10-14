# Outputs for the rds module (PETPLAT-22/23) — consumed by the environment
# roots, K8s ConfigMaps (connection strings), and the ExternalSecret that
# syncs the credentials into the cluster (PETPLAT-35).

output "endpoint" {
  description = "RDS endpoint hostname (without port) — e.g. petclinic-dev-mysql.abc123.us-east-1.rds.amazonaws.com."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS listener port (3306 for MySQL)."
  value       = aws_db_instance.this.port
}

output "db_instance_id" {
  description = "RDS DB instance identifier (petclinic-{env}-mysql)."
  value       = aws_db_instance.this.id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS master credentials (petclinic/{env}/rds-credentials)."
  value       = aws_secretsmanager_secret.rds.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret (petclinic/{env}/rds-credentials) — the remoteRef key used by the ExternalSecret."
  value       = aws_secretsmanager_secret.rds.name
}

output "db_name" {
  description = "Name of the shared database created on the instance (petclinic)."
  value       = var.db_name
}

output "master_username" {
  description = "Master username for the petclinic database (also stored in the Secrets Manager secret)."
  value       = var.master_username
}

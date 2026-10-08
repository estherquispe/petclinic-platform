# Outputs for the dev environment root module.

output "aws_region" {
  description = "AWS region for this environment."
  value       = var.aws_region
}

output "environment" {
  description = "Environment name (dev or prod)."
  value       = var.environment
}

output "project" {
  description = "Project name."
  value       = var.project
}

# VPC networking outputs (PETPLAT-9) — consumed by EKS, RDS, and ALB stories.

output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the dev public subnets."
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "EKS cluster security group ID."
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID."
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID."
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = module.vpc.alb_sg_id
}

# EKS outputs (PETPLAT-12/13/14).

# output "cluster_name" {
#   description = "EKS cluster name."
#   value       = module.eks.cluster_name
# }

# output "cluster_endpoint" {
#   description = "EKS API server endpoint."
#   value       = module.eks.cluster_endpoint
# }

# output "cluster_ca_certificate" {
#   description = "Base64-encoded cluster CA certificate."
#   value       = module.eks.cluster_ca_certificate
# }

# output "oidc_provider_arn" {
#   description = "IAM OIDC provider ARN (IRSA)."
#   value       = module.eks.oidc_provider_arn
# }

# output "oidc_provider_url" {
#   description = "OIDC issuer URL without scheme (IRSA conditions)."
#   value       = module.eks.oidc_provider_url
# }

# output "node_group_name" {
#   description = "Managed node group name."
#   value       = module.eks.node_group_name
# }

# output "node_group_arn" {
#   description = "Managed node group ARN."
#   value       = module.eks.node_group_arn
# }

# output "cluster_primary_security_group_id" {
#   description = "Security group created by EKS for the cluster ENIs."
#   value       = module.eks.cluster_primary_security_group_id
# }

# output "node_role_arn" {
#   description = "Worker node IAM role ARN."
#   value       = module.eks.node_role_arn
# }

# output "kubeconfig_update_command" {
#   description = "Run this command to configure kubectl for the cluster (PETPLAT-14)."
#   value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
# }

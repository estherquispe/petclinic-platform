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
  description = "ID of the Terraform-managed ALB security group. NOTE: the live ALB created by the AWS Load Balancer Controller uses controller-managed security groups instead (see k8s/base/ingress/ingress.yaml) — this SG is the Terraform-side baseline perimeter per the technical spec, not the live ALB's SG."
  value       = module.vpc.alb_sg_id
}

# EKS outputs (PETPLAT-12/13/14).

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.eks.cluster_ca_certificate
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN (IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL without scheme (IRSA conditions)."
  value       = module.eks.oidc_provider_url
}

output "node_group_name" {
  description = "Managed node group name."
  value       = module.eks.node_group_name
}

output "node_group_arn" {
  description = "Managed node group ARN."
  value       = module.eks.node_group_arn
}

output "cluster_primary_security_group_id" {
  description = "Security group created by EKS for the cluster ENIs."
  value       = module.eks.cluster_primary_security_group_id
}

output "node_role_arn" {
  description = "Worker node IAM role ARN."
  value       = module.eks.node_role_arn
}

output "kubeconfig_update_command" {
  description = "Run this command to configure kubectl for the cluster (PETPLAT-14)."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# ECR outputs (PETPLAT-18/20) — consumed by CI (image push targets) and K8s
# manifests (image references).

output "ecr_repository_urls" {
  description = "Map of service_name → dev ECR repository URL."
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service_name → dev ECR repository ARN."
  value       = module.ecr.repository_arns
}

output "ecr_image_tag_mutability" {
  description = "Effective tag mutability of the dev ECR repositories (MUTABLE for dev)."
  value       = module.ecr.image_tag_mutability
}

# RDS outputs (PETPLAT-22/23/25) — connection info for K8s ConfigMaps
# (docs/database-init.md) and the secret ARN for the External Secrets
# Operator (PETPLAT-35).

output "rds_endpoint" {
  description = "RDS endpoint hostname (jdbc:mysql://{rds_endpoint}:3306/petclinic)."
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS listener port."
  value       = module.rds.port
}

output "rds_instance_id" {
  description = "RDS DB instance identifier (petclinic-dev-mysql)."
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "ARN of the petclinic/dev/rds-credentials secret in Secrets Manager."
  value       = module.rds.secret_arn
}

# DNS / TLS outputs (PETPLAT-28/31/32) — the certificate ARN is consumed by
# k8s/base/ingress/ingress.yaml (alb.ingress.kubernetes.io/certificate-arn).

output "dns_zone_id" {
  description = "ID of the existing Route 53 public hosted zone for domain_name."
  value       = module.dns.zone_id
}

output "dns_name_servers" {
  description = "NS delegation records of the hosted zone (already delegated for the registered domain)."
  value       = module.dns.name_servers
}

output "dns_certificate_arn" {
  description = "ARN of the DNS-validated wildcard ACM certificate (*.{domain_name}). Reference this in the ALB Ingress manifest."
  value       = module.dns.certificate_arn
}

output "dns_record_fqdn" {
  description = "FQDN of the petclinic-dev.{domain_name} alias A record → ALB (null until alb_dns_name/alb_hosted_zone_id are set in terraform.tfvars — PETPLAT-31)."
  value       = module.dns.record_fqdn
}

# AWS Load Balancer Controller outputs (PETPLAT-29) — the role ARN is passed to
# scripts/install-lb-controller.sh as the ServiceAccount IRSA annotation.

output "lb_controller_role_arn" {
  description = "IAM role ARN for the kube-system/aws-load-balancer-controller ServiceAccount (IRSA)."
  value       = module.eks.lb_controller_role_arn
}


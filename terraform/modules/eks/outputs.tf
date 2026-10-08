# Outputs for the eks module — consumed by environment roots and downstream
# modules (Helm, ArgoCD, IRSA consumers).

output "cluster_name" {
  description = "EKS cluster name (petclinic-{env})."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate (for kubeconfig)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (for IRSA trust policies)."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix (for IRSA condition variables)."
  value       = local.oidc_provider
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.main.node_group_name
}

output "node_group_arn" {
  description = "ARN of the managed node group (observability/backup tooling)."
  value       = aws_eks_node_group.main.arn
}

output "cluster_primary_security_group_id" {
  description = "Security group created by EKS and attached to the cluster ENIs."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  description = "IAM role ARN assumed by worker nodes."
  value       = aws_iam_role.node.arn
}

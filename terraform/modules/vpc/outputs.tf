# Outputs for the vpc module — consumed by downstream modules (EKS, RDS, DNS).

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (one per AZ)."
  value       = aws_subnet.public[*].id
}

# Alias matching the PETPLAT-6 acceptance criteria ("Outputs: vpc_id, subnet_ids").
output "subnet_ids" {
  description = "IDs of the public subnets (alias of public_subnet_ids)."
  value       = aws_subnet.public[*].id
}

output "eks_cluster_sg_id" {
  description = "EKS cluster (control plane) security group ID."
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID."
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "RDS security group ID."
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}

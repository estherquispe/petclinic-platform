# Prod environment root module.
# Foundation (PETPLAT-1/4/5) + VPC networking (PETPLAT-6/8/10).
# Later epics add EKS, ECR, RDS, DNS, secrets, and observability
# by calling the shared modules in ../../modules/.

# VPC: 2 public subnets across 2 AZs, IGW, baseline security groups.
# technical-spec.md → VPC Network Design (prod CIDRs, non-overlapping with
# dev), no NAT Gateway.
module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr            = "10.1.0.0/16"
  public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  availability_zones  = ["us-east-1a", "us-east-1b"]
}

data "aws_caller_identity" "current" {}

# EKS cluster: petclinic-prod, Kubernetes 1.36, managed node group t4g.small
# (min 2 / max 4 / desired 2) in the public subnets.
# technical-spec.md → EKS Cluster (PETPLAT-12/13/14/17).
module "eks" {
  source = "../../modules/eks"

  project         = var.project
  environment     = var.environment
  cluster_version = "1.36"

  # Network + baseline security groups from the VPC module (PETPLAT-10).
  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  # Prod sizing is intentionally identical to dev for this learning project
  # (technical-spec.md → Managed Node Group cost note).
  node_instance_types = ["t4g.small"]
  node_min_size       = 2
  node_max_size       = 4
  node_desired_size   = 2

  # PETPLAT-14: deployer gets explicit cluster-admin access entry.
  # Falls back to the deploying caller; set eks_admin_principal_arns to use a
  # specific IAM user/role (e.g. when running via an assumed-role session).
  admin_principal_arns = length(var.eks_admin_principal_arns) > 0 ? var.eks_admin_principal_arns : [data.aws_caller_identity.current.arn]

  # Review fix: restrict the public API endpoint to known CIDRs
  # (set api_server_public_access_cidrs in terraform.tfvars).
  api_server_public_access_cidrs = var.api_server_public_access_cidrs
}

# RDS: shared MySQL 8.0 instance (petclinic-prod-mysql) for customers/visits/
# vets, plus the master-credentials secret in Secrets Manager
# (PETPLAT-22/23/27). technical-spec.md → RDS Database (prod column).
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  # Network from the VPC module (PETPLAT-10): subnets for the DB subnet group
  # and the RDS SG that admits 3306 from the EKS node SG only.
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  # Prod values per PETPLAT-27:
  instance_class = "db.t4g.micro" # free tier for this learning project — real prod: db.r7g.large+ (spec cost note)
  multi_az       = false          # single-AZ to save cost — enable Multi-AZ in real production
  # Take a final snapshot when the instance is destroyed (data-preserving).
  skip_final_snapshot     = false
  backup_retention_period = 30 # 30 days for prod (PETPLAT-27)

  # Explicit per technical-spec.md → RDS Database: deletion_protection is
  # false in both envs (students destroy after each session). Set true in a
  # real production deployment — it blocks `terraform destroy` entirely.
  deletion_protection = false
}

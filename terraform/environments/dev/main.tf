# Dev environment root module.
# Foundation (PETPLAT-1/3/4/5) + VPC networking (PETPLAT-6/8/9).
# Later epics add EKS, ECR, RDS, DNS, secrets, and observability
# by calling the shared modules in ../../modules/.

# VPC: 2 public subnets across 2 AZs, IGW, baseline security groups.
# technical-spec.md → VPC Network Design (dev CIDRs), no NAT Gateway.
module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones  = ["us-east-1a", "us-east-1b"]
}

data "aws_caller_identity" "current" {}

# EKS cluster: petclinic-dev, Kubernetes 1.36, managed node group t4g.small
# (min 2 / max 4 / desired 2) in the public subnets.
# technical-spec.md → EKS Cluster (PETPLAT-12/13/14/15).
module "eks" {
  source = "../../modules/eks"

  project         = var.project
  environment     = var.environment
  cluster_version = "1.36"

  # Network + baseline security groups from the VPC module (PETPLAT-9).
  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  # Dev sizing per technical-spec.md → Managed Node Group.
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

# ECR: one private repository per service under petclinic-dev/, with
# scan-on-push, lifecycle policies, and MUTABLE tags for dev (PETPLAT-18/19/20).
# technical-spec.md → ECR Container Registry.
module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]

  # image_tag_mutability is left unset: the module derives MUTABLE for dev
  # (allows re-pushing the same tag during development) and IMMUTABLE for prod.
  # force_delete lets `terraform destroy` remove dev repos that still contain
  # images (students destroy after each session — technical-spec.md cost note).
  force_delete = true
}

# RDS: shared MySQL 8.0 instance (petclinic-dev-mysql) for customers/visits/
# vets, plus the master-credentials secret in Secrets Manager
# (PETPLAT-22/23/25). technical-spec.md → RDS Database (dev column).
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  # Network from the VPC module (PETPLAT-9): subnets for the DB subnet group
  # and the RDS SG that admits 3306 from the EKS node SG only.
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  # Dev values per PETPLAT-25:
  instance_class = "db.t4g.micro" # free tier (ARM/Graviton)
  multi_az       = false          # cost optimization for the learning project
  # Fast teardown for dev (students destroy after each session).
  skip_final_snapshot     = true
  backup_retention_period = 7 # 7 days for dev (PETPLAT-25)

  # Dev-only: immediate secret deletion so `terraform destroy` can re-create
  # petclinic/dev/rds-credentials with the same name on the next session
  # (review fix — prod keeps the 30-day default, enforced by a precondition).
  secret_recovery_window_in_days = 0
}


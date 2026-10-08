# vpc module — VPC, subnets, internet gateway, route table, baseline security groups.
# All-public subnet design: no NAT Gateway, no private subnets, no VPC endpoints
# (ADR-0001 — cost optimization for students). Security groups are the perimeter.
#
# Technical spec: docs/technical-spec.md → VPC Network Design, Security Groups
# Stories: PETPLAT-6 (VPC), PETPLAT-8 (security groups)

locals {
  # Tags merged into every resource in this module. Project/Environment/ManagedBy
  # mirror the provider default_tags; Component is the module-level classification
  # (technical-spec.md → Optional Tags). var.tags allows extra service tags.
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "networking"
    },
    var.tags,
  )

  # Tag key EKS requires on every subnet the cluster uses.
  eks_cluster_tag = "kubernetes.io/cluster/${var.project}-${var.environment}"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-vpc"
  })
}

# -----------------------------------------------------------------------------
# Public subnets — 2 subnets across 2 AZs. ALL resources (EKS nodes, RDS, ALB)
# run in public subnets; there are intentionally no private subnets.
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.tags,
    {
      Name                     = "${var.project}-${var.environment}-public-${count.index + 1}"
      "kubernetes.io/role/elb" = "1"
    },
    { (local.eks_cluster_tag) = "shared" },
  )
}

# -----------------------------------------------------------------------------
# Internet gateway + single public route table (0.0.0.0/0 → IGW)
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-public-rt"
  })
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Baseline security groups — the primary access control boundary in this
# all-public design. They must be as restrictive as a traditional private
# subnet setup (PETPLAT-8).
#
# Cross-SG rules are standalone aws_security_group_rule resources so that
# mutually referencing groups (cluster ↔ node ↔ ALB) do not create a
# dependency cycle in the resource graph.
# -----------------------------------------------------------------------------

# EKS cluster (control plane) security group.
resource "aws_security_group" "eks_cluster" {
  name        = "${var.project}-${var.environment}-eks-cluster"
  description = "EKS control plane — HTTPS (443) reachable from worker nodes only"
  vpc_id      = aws_vpc.main.id

  # API server egress: all traffic (technical-spec.md → Security Groups).
  egress {
    description = "All outbound traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-eks-cluster-sg"
  })
}

# EKS worker node security group.
resource "aws_security_group" "eks_node" {
  name        = "${var.project}-${var.environment}-eks-node"
  description = "EKS worker nodes — traffic from control plane, peer nodes, and ALB only"
  vpc_id      = aws_vpc.main.id

  # All outbound traffic (technical-spec.md → Security Groups).
  egress {
    description = "All outbound traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-eks-node-sg"
  })
}

# RDS (MySQL) security group — 3306 from EKS nodes ONLY, never 0.0.0.0/0.
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds"
  description = "RDS MySQL — port 3306 reachable from EKS worker nodes only"
  vpc_id      = aws_vpc.main.id

  # Default outbound; RDS does not initiate connections.
  egress {
    description = "All outbound traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-rds-sg"
  })
}

# ALB security group — the only group with internet-facing ingress (80/443).
# Egress is restricted to the worker-node ports (inline rules replace the
# AWS default allow-all egress rule).
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb"
  description = "Public ALB — HTTP/HTTPS from internet, egress to worker nodes only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "NodePort services to worker nodes"
    protocol        = "tcp"
    from_port       = 30000
    to_port         = 32767
    security_groups = [aws_security_group.eks_node.id]
  }

  egress {
    description     = "Health checks to worker nodes"
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.eks_node.id]
  }

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-alb-sg"
  })
}

# --- Cross-security-group rules ---------------------------------------------

# EKS cluster SG: API server access from nodes.
resource "aws_security_group_rule" "eks_cluster_ingress_api_from_nodes" {
  type                     = "ingress"
  description              = "HTTPS (443) from EKS worker nodes"
  security_group_id        = aws_security_group.eks_cluster.id
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.eks_node.id
}

# EKS node SG: all traffic from the control plane.
resource "aws_security_group_rule" "eks_node_ingress_from_cluster" {
  type                     = "ingress"
  description              = "All traffic from EKS control plane"
  security_group_id        = aws_security_group.eks_node.id
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  source_security_group_id = aws_security_group.eks_cluster.id
}

# EKS node SG: inter-node communication (self-reference).
resource "aws_security_group_rule" "eks_node_ingress_self" {
  type              = "ingress"
  description       = "All traffic between worker nodes"
  security_group_id = aws_security_group.eks_node.id
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  self              = true
}

# EKS node SG: kubelet API from the control plane.
resource "aws_security_group_rule" "eks_node_ingress_kubelet_from_cluster" {
  type                     = "ingress"
  description              = "Kubelet API (10250) from EKS control plane"
  security_group_id        = aws_security_group.eks_node.id
  protocol                 = "tcp"
  from_port                = 10250
  to_port                  = 10250
  source_security_group_id = aws_security_group.eks_cluster.id
}

# EKS node SG: NodePort services from the ALB.
resource "aws_security_group_rule" "eks_node_ingress_nodeport_from_alb" {
  type                     = "ingress"
  description              = "NodePort services (30000-32767) from ALB"
  security_group_id        = aws_security_group.eks_node.id
  protocol                 = "tcp"
  from_port                = 30000
  to_port                  = 32767
  source_security_group_id = aws_security_group.alb.id
}

# RDS SG: MySQL from EKS worker nodes ONLY — never 0.0.0.0/0.
resource "aws_security_group_rule" "rds_ingress_mysql_from_nodes" {
  type                     = "ingress"
  description              = "MySQL (3306) from EKS worker nodes"
  security_group_id        = aws_security_group.rds.id
  protocol                 = "tcp"
  from_port                = 3306
  to_port                  = 3306
  source_security_group_id = aws_security_group.eks_node.id
}


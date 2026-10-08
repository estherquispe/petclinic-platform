# eks module — EKS cluster, managed node group, OIDC provider (IRSA), IAM roles,
# access entries, and EKS managed add-ons.
# All-public subnet design (ADR-0001): control plane and nodes use public subnets.
#
# Technical spec: docs/technical-spec.md → EKS Cluster, IRSA Roles, Terraform Modules
# Stories: PETPLAT-12 (cluster/IAM/OIDC), PETPLAT-13 (node group), PETPLAT-14 (access),
#          PETPLAT-84 (add-ons)

locals {
  # Tags merged into every resource. Component is the module-level classification
  # (technical-spec.md → Optional Tags); var.tags allows extra service tags.
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "compute"
    },
    var.tags,
  )

  cluster_name    = "${var.project}-${var.environment}"       # petclinic-dev / petclinic-prod
  node_group_name = "${var.project}-${var.environment}-nodes" # petclinic-dev-nodes
  oidc_provider   = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

# -----------------------------------------------------------------------------
# Cluster IAM role (technical-spec.md → Cluster IAM Role)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project}-${var.environment}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -----------------------------------------------------------------------------
# KMS key for Kubernetes secrets encryption (review fix: CIS EKS Benchmark
# 5.4.1 — envelope-encrypt Secrets with KMS).
# -----------------------------------------------------------------------------

resource "aws_kms_key" "cluster_secrets" {
  description             = "EKS Kubernetes secrets encryption for ${local.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "cluster_secrets" {
  name          = "alias/${var.project}-${var.environment}-eks-secrets"
  target_key_id = aws_kms_key.cluster_secrets.key_id
}

# -----------------------------------------------------------------------------
# EKS cluster (technical-spec.md → EKS Cluster → Cluster Configuration)
# -----------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  # Cluster logging: api, audit, authenticator (spec requirement).
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Kubernetes Secrets are envelope-encrypted with a dedicated KMS key.
  encryption_config {
    provider {
      key_arn = aws_kms_key.cluster_secrets.arn
    }

    resources = ["secrets"]
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # Do NOT auto-grant the cluster creator implicit admin. Access is granted
    # explicitly below via aws_eks_access_entry (PETPLAT-14), so it is
    # Terraform-managed, reviewable, and revocable.
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_sg_id] # baseline cluster SG from VPC module
    endpoint_public_access  = true                # required by spec (API Server Endpoint: Public)
    endpoint_private_access = true                # free hardening: in-VPC path to the API
    public_access_cidrs     = var.api_server_public_access_cidrs
  }

  tags = merge(local.tags, {
    Name = local.cluster_name
  })

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# -----------------------------------------------------------------------------
# Cluster access entries (PETPLAT-14)
#
# With bootstrap_cluster_creator_admin_permissions = false, NO principal has
# Kubernetes access until an access entry exists. The deploying principal(s)
# are granted cluster admin explicitly here. To add more users/roles later,
# append their IAM principal ARNs to var.admin_principal_arns
# (see docs/runbooks/eks-access-and-addons.md).
# -----------------------------------------------------------------------------

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = local.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# -----------------------------------------------------------------------------
# OIDC provider for IRSA (PETPLAT-12, technical-spec.md → IRSA Roles)
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "eks" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  # AWS stopped validating thumbprints for its own OIDC endpoints; this value
  # (StarField Services Root CA G2 — signer of EKS OIDC endpoints) is kept for
  # tooling compatibility and has no effect on trust evaluation.
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]

  tags = merge(local.tags, {
    Name = "${local.cluster_name}-oidc"
  })
}

# -----------------------------------------------------------------------------
# Node IAM role (technical-spec.md → Node IAM Role Policies)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project}-${var.environment}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# Launch template — attaches the VPC module's node security group, enforces
# IMDSv2, and configures the encrypted root volume (disk size is set here
# because launch templates and aws_eks_node_group.disk_size are mutually
# exclusive).
# -----------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix            = "${local.cluster_name}-nodes-"
  description            = "Launch template for ${local.node_group_name} managed node group"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 enforced
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Baseline node security group from the VPC module (PETPLAT-8).
  vpc_security_group_ids = [var.node_sg_id]

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name = "${local.cluster_name}-node"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.tags, {
      Name = "${local.cluster_name}-node-volume"
    })
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Managed node group (PETPLAT-13, technical-spec.md → Managed Node Group)
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = local.node_group_name
  version         = var.cluster_version
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids # public subnets (all-public design)

  ami_type       = var.node_ami_type
  capacity_type  = "ON_DEMAND" # Graviton free trial — not Spot
  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  # Review fix: automatically replace nodes that fail EC2/kubelet health checks.
  node_repair_config {
    enabled = true
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }

  dynamic "taint" {
    for_each = var.node_taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.tags, {
    Name = local.node_group_name
  })

  depends_on = [aws_iam_role_policy_attachment.node]
}

# -----------------------------------------------------------------------------
# IRSA: EBS CSI Driver role (PETPLAT-84, technical-spec.md → IRSA Roles)
# Trust is scoped to exactly one ServiceAccount: kube-system/ebs-csi-controller-sa
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  # Name matches technical-spec.md → IRSA Roles: petclinic-{env}-ebs-csi-role
  name               = "${var.project}-${var.environment}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# -----------------------------------------------------------------------------
# EKS managed add-ons (PETPLAT-84, technical-spec.md → EKS Managed Add-ons)
# Versions are PINNED via var.addon_versions — never "latest".
# Upgrade procedure: docs/runbooks/eks-access-and-addons.md
# -----------------------------------------------------------------------------

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = var.addon_versions["coredns"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = var.addon_versions["kube-proxy"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_versions["vpc-cni"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.addon_versions["aws-ebs-csi-driver"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn # IRSA

  tags = local.tags

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}

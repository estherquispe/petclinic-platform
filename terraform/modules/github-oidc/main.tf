# github-oidc module — OIDC federation between GitHub Actions and AWS
# (PETPLAT-52, technical-spec.md → CI/CD Pipeline → OIDC Federation).
#
# Creates:
#   1. aws_iam_openid_connect_provider for token.actions.githubusercontent.com
#   2. aws_iam_role petclinic-github-actions-role whose trust policy restricts
#      token.actions.githubusercontent.com:sub to the application repo fork
#      and main branch ONLY:
#          repo:estherquispe/spring-petclinic-microservices:ref:refs/heads/main
#      (derived from the app repo remote URL — never the platform repo, never *)
#   3. aws_iam_role_policy with ECR-only push permissions:
#      ecr:GetAuthorizationToken, ecr:BatchCheckLayerAvailability,
#      ecr:InitiateLayerUpload, ecr:UploadLayerPart, ecr:CompleteLayerUpload,
#      ecr:PutImage. No ecr:*, no *, no non-ECR permissions.
#
# No long-lived AWS credentials — GitHub Actions authenticates via
# sts:AssumeRoleWithWebIdentity (aws-actions/configure-aws-credentials with
# role-to-assume).
#
# Stories: PETPLAT-52

locals {
  # Tags merged into every resource. Project/Environment/ManagedBy mirror the
  # provider default_tags (technical-spec.md → Required Tags).
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "iam"
    },
    var.tags,
  )

  # OIDC provider URL with scheme, used in the trust policy condition keys:
  #   {url}:sub  and  {url}:aud
  provider_url = "https://${var.oidc_provider_url}"

  # Federated subject — application repo fork + main branch only.
  # Derived from `git -C <app-repo> remote get-url origin`:
  #   https://github.com/estherquispe/spring-petclinic-microservices.git
  sub = "repo:${var.github_repository}:ref:refs/heads/main"
}

# -----------------------------------------------------------------------------
# OIDC provider — GitHub Actions (token.actions.githubusercontent.com).
# Thumbprint is the SHA-1 of the GitHub Actions OIDC CA leaf certificate.
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = local.provider_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["a031c46782e6e6c662c2c87c761eaa3d443864ab"]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# IAM role — assumed by GitHub Actions via OIDC web identity.
# Action: sts:AssumeRoleWithWebIdentity (never sts:AssumeRole).
# -----------------------------------------------------------------------------

resource "aws_iam_role" "github_actions" {
  name = var.role_name
  path = "/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${aws_iam_openid_connect_provider.github.url}:aud" = "sts.amazonaws.com"
            "${aws_iam_openid_connect_provider.github.url}:sub" = local.sub
          }
        }
      }
    ]
  })

  description = "OIDC role for GitHub Actions CI - ECR push only; assumed via sts:AssumeRoleWithWebIdentity (no long-lived keys)"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Inline policy — ECR push only (PETPLAT-52 acceptance criteria).
# ecr:GetAuthorizationToken is account-scoped so it requires Resource: "*".
# All image push actions are scoped to the environment's repository ARNs.
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "ecr_push" {
  name = "${var.role_name}-ecr-push"
  role = aws_iam_role.github_actions.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRGetAuthorizationToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid    = "ECRPushImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = var.repository_arns
      }
    ]
  })
}
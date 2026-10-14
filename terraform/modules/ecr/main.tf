# ecr module — one ECR private repository per microservice with scan-on-push,
# configurable tag immutability, and lifecycle policies that bound image
# storage (technical-spec.md → ECR Container Registry).
#
# Repos are namespaced per environment: petclinic-{env}/{service}, so dev and
# prod images are fully isolated.
#
# Stories: PETPLAT-18 (module), PETPLAT-19 (lifecycle policy + immutability)

locals {
  # Tags merged into every repository. Project/Environment/ManagedBy mirror the
  # provider default_tags; Component is the module-level classification
  # (technical-spec.md → Optional Tags). var.tags allows extra service tags.
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "container-registry"
    },
    var.tags,
  )

  # Tag mutability is variable-driven: an explicit value wins, otherwise it is
  # derived from the environment — MUTABLE for dev (re-push the same tag during
  # development), IMMUTABLE for prod (deployed tags cannot be overwritten).
  image_tag_mutability = coalesce(
    var.image_tag_mutability,
    var.environment == "prod" ? "IMMUTABLE" : "MUTABLE",
  )

  # Lifecycle policy (PETPLAT-19, technical-spec.md → Lifecycle Policies):
  # keep the 10 most recent TAGGED images and expire untagged images after
  # 7 days to keep ECR storage at ~$1/month. The untagged rule runs
  # first (priority 1) so stale layers are always reclaimed on schedule and can
  # never crowd tagged releases out of the count-based rule (review fix).
  # Note: ECR's schema has no "olderThanSeconds" field — age-based expiry uses
  # countType=sinceImagePushed with countUnit=days.
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# Repositories — one per service. URIs follow
# {account}.dkr.ecr.{region}.amazonaws.com/petclinic-{env}/{service}:{tag}.
# Encryption is AES256 (ECR default — technical-spec.md → Encryption Matrix).
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "service" {
  for_each             = toset(var.service_names)
  name                 = "${var.project}-${var.environment}/${each.value}"
  image_tag_mutability = local.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  # Explicit AES256 (SSE-S3) — the ECR default per technical-spec.md →
  # Encryption Matrix, pinned here so a change of account defaults cannot
  # silently alter encryption (review fix).
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.tags,
    {
      Name    = "${var.project}-${var.environment}/${each.value}"
      Service = each.value
    },
  )
}

# -----------------------------------------------------------------------------
# Lifecycle policy attached to every repository (PETPLAT-19).
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name
  policy     = local.lifecycle_policy
}


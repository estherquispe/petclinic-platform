# AWS provider configuration — dev environment.
provider "aws" {
  region = var.aws_region

  # Required tags applied to every AWS resource in this environment
  # (technical-spec.md → General Project Parameters → Required Tags).
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# S3 backend for prod remote state (technical-spec.md → Terraform State Backend).
#
# Remote state is ACTIVE (review fix H-1): `terraform init` configured this
# backend — state lives in S3 with SSE + DynamoDB locking, never on disk here.
# Bucket/table were bootstrapped by scripts/bootstrap-state.sh (PETPLAT-2).
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-409297710841"
    key            = "petclinic/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}

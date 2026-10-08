# S3 backend for dev remote state (technical-spec.md → Terraform State Backend).
#
# Bucket/table bootstrapped by scripts/bootstrap-state.sh (PETPLAT-2).
# If you change accounts, replace the account ID in the bucket name below,
# then re-run: terraform init -reconfigure
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-409297710841"
    key            = "petclinic/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}

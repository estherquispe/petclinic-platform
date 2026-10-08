# S3 backend for prod remote state (technical-spec.md → Terraform State Backend).
#
# NOTE: state is currently kept LOCAL for this machine (billing decision).
# Initialize without contacting AWS:
#   terraform init -backend=false
# To enable remote state later: run scripts/bootstrap-state.sh (PETPLAT-2),
# replace {account-id} with the real AWS account ID, then:
#   terraform init -reconfigure
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-409297710841"
    key            = "petclinic/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}

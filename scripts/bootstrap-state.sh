#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — One-time setup of Terraform remote state backend (PETPLAT-2)
#
# Provisions the S3 bucket and DynamoDB table used for Terraform remote state
# (technical-spec.md → Terraform State Backend). Run this ONCE per AWS account,
# before the first `terraform init` with the S3 backend enabled.
#
# Creates (idempotent — safe to run multiple times):
#   - S3 bucket  petclinic-terraform-state-{account-id}
#       · versioning enabled
#       · server-side encryption (AES256 / SSE-S3)
#       · public access blocked (all 4 settings)
#   - DynamoDB table  petclinic-terraform-locks
#       · partition key LockID (String) — state locking
#
# Usage:
#   ./scripts/bootstrap-state.sh                 # region defaults to us-east-1
#   ./scripts/bootstrap-state.sh --region us-west-2
#

REGION="us-east-1"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo "  --region: AWS region for the state bucket (default: us-east-1)"
  echo ""
  echo "Examples:"
  echo "  $0                        # Bootstrap state backend in us-east-1"
  echo "  $0 --region us-west-2     # Bootstrap state backend in us-west-2"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      if [[ $# -lt 2 ]]; then
        echo "Error: --region requires a value"
        usage
      fi
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: unknown argument '$1'"
      usage
      ;;
  esac
done

# --- Resolve AWS account ID (used in the bucket name) ---
ACCOUNT_ID=$(aws sts get-caller-identity \
  --query 'Account' \
  --output text)

if [[ -z "${ACCOUNT_ID}" || "${ACCOUNT_ID}" == "None" ]]; then
  echo "Error: unable to resolve AWS account ID. Check your credentials."
  exit 1
fi

BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="petclinic-terraform-locks"

echo "============================================"
echo "  Bootstrapping Terraform state backend"
echo "  Region:      ${REGION}"
echo "  Account:     ${ACCOUNT_ID}"
echo "  S3 Bucket:   ${BUCKET_NAME}"
echo "  DynamoDB:    ${TABLE_NAME}"
echo "============================================"
echo ""

# --- S3 Bucket ---
echo "[1/3] S3 bucket: ${BUCKET_NAME}"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null; then
  echo "  -> Bucket already exists. Ensuring settings..."
else
  echo "  -> Creating bucket..."
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    $( [[ "${REGION}" != "us-east-1" ]] && echo "--create-bucket-configuration LocationConstraint=${REGION}" ) \
    > /dev/null
  echo "  -> Bucket created."
fi

echo "  -> Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --versioning-configuration Status=Enabled

echo "  -> Enabling server-side encryption (AES256)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'

echo "  -> Blocking public access (all 4 settings)..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo ""

# --- DynamoDB Table ---
echo "[2/3] DynamoDB table: ${TABLE_NAME}"

TABLE_STATUS=$(aws dynamodb describe-table \
  --table-name "${TABLE_NAME}" \
  --region "${REGION}" \
  --query 'Table.TableStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "${TABLE_STATUS}" == "NOT_FOUND" ]]; then
  echo "  -> Creating table (partition key: LockID, String)..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    > /dev/null

  echo "  -> Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}"
  echo "  -> Table created."
else
  echo "  -> Table already exists (status: ${TABLE_STATUS})."
fi

echo ""

# --- Summary ---
echo "[3/3] Done."
echo "============================================"
echo "  State backend ready."
echo ""
echo "  Next steps:"
echo "    1. Set the bucket name in"
echo "       terraform/environments/{dev,prod}/backend.tf:"
echo "         bucket = \"${BUCKET_NAME}\""
echo "    2. Initialize each environment:"
echo "         cd terraform/environments/dev && terraform init -reconfigure"
echo "         cd terraform/environments/prod && terraform init -reconfigure"
echo "============================================"
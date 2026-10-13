#!/usr/bin/env bash
set -euo pipefail

#
# ecr-login.sh — Authenticate Docker to the ECR private registry (PETPLAT-21)
#
# Pipes an ECR authorization token into `docker login` so images can be pulled
# from / pushed to {account}.dkr.ecr.{region}.amazonaws.com.
# Works on macOS and Linux.
#
# Usage:
#   ./scripts/ecr-login.sh                    # region defaults to us-east-1
#   ./scripts/ecr-login.sh --region us-west-2
#

REGION="us-east-1"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo "  --region: AWS region of the ECR registry (default: us-east-1)"
  echo ""
  echo "Examples:"
  echo "  $0                        # Login to ECR in us-east-1"
  echo "  $0 --region us-west-2     # Login to ECR in us-west-2"
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

# --- Resolve AWS account ID (part of the registry hostname) ---
ACCOUNT_ID=$(aws sts get-caller-identity \
  --query 'Account' \
  --output text)

if [[ -z "${ACCOUNT_ID}" || "${ACCOUNT_ID}" == "None" ]]; then
  echo "Error: unable to resolve AWS account ID. Check your credentials."
  exit 1
fi

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ${REGISTRY} (region: ${REGION})..."

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

echo "Login succeeded: ${REGISTRY}"

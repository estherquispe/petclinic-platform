#!/usr/bin/env bash
set -euo pipefail

#
# install-lb-controller.sh — Install the AWS Load Balancer Controller on EKS (PETPLAT-29)
#
# Installs the controller from the official Helm chart (aws-load-balancer-controller
# from https://eks.amazonaws.com/charts) into kube-system, wired to the Terraform-
# created IRSA role petclinic-{env}-lb-controller-role (technical-spec.md → IRSA
# Roles) via the ServiceAccount annotation eks.amazonaws.com/role-arn, applies the
# "alb" IngressClass, and verifies the rollout.
#
# Prerequisites:
#   - kubectl, helm and the AWS CLI on PATH; AWS credentials for the target account
#   - EKS cluster + VPC applied (terraform apply in terraform/environments/{env})
#     — that apply also creates the IRSA role this script looks up
#   - kubectl configured for the cluster (aws eks update-kubeconfig --name <cluster>)
#
# Version pinning (IMPORTANT): the controller has TWO version numbers that use
# different schemes:
#   - Helm chart version  → --chart-version (e.g. 3.6.0, published on
#                            eks.amazonaws.com/charts)
#   - Application version → --app-version (e.g. v3.6.0 — the Git tag on
#                            kubernetes-sigs/aws-load-balancer-controller used to
#                            fetch the CRD manifests; note the leading "v")
# Fetching the CRDs from GitHub with the chart version instead of the app version
# tag returns 404 — the two numbering schemes differ (e.g. chart 1.8.1 ↔ app
# v2.8.1). Keep both in sync with the chart's appVersion field when upgrading.
#
# Usage:
#   ./scripts/install-lb-controller.sh --cluster-name petclinic-dev
#   ./scripts/install-lb-controller.sh --cluster-name petclinic-dev \
#       --role-arn arn:aws:iam::123456789012:role/petclinic-dev-lb-controller-role
#
# Options:
#   --cluster-name NAME     EKS cluster name (required, e.g. petclinic-dev)
#   --role-arn ARN          IRSA role ARN for the ServiceAccount. Default: looked
#                           up as ${cluster-name}-lb-controller-role via the AWS CLI.
#   --region REGION         AWS region of the cluster (default: us-east-1)
#   --namespace NAMESPACE   Install namespace (default: kube-system, per spec)
#   --chart-version VERSION Helm chart version (default: 3.6.0)
#   --app-version TAG       Controller application Git tag used for the CRDs on
#                           GitHub (default: v3.6.0)
#   -h, --help              Show this help
#
# Environment:
#   WAIT_TIMEOUT            helm --wait timeout (default: 5m)
#
# After a successful install (also printed at the end):
#   1. Put the ACM certificate ARN into k8s/base/ingress/ingress.yaml
#      (terraform -chdir=terraform/environments/dev output -raw dns_certificate_arn)
#   2. kubectl apply -f k8s/base/ingress/ingress.yaml — the controller creates the
#      internet-facing ALB
#   3. PETPLAT-31: point the DNS record at the ALB — set alb_dns_name and
#      alb_hosted_zone_id in terraform/environments/dev/terraform.tfvars and
#      run terraform apply
#

RELEASE_NAME="aws-load-balancer-controller"
SERVICE_ACCOUNT="aws-load-balancer-controller"
NAMESPACE="kube-system"
CLUSTER_NAME=""
REGION="us-east-1"
ROLE_ARN=""
CHART_VERSION="3.6.0"
APP_VERSION="v3.6.0"

usage() {
  sed -n '3,63p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name)
      [[ $# -ge 2 ]] || { echo "Error: --cluster-name requires a value" >&2; usage 1; }
      CLUSTER_NAME="$2"; shift 2 ;;
    --role-arn)
      [[ $# -ge 2 ]] || { echo "Error: --role-arn requires a value" >&2; usage 1; }
      ROLE_ARN="$2"; shift 2 ;;
    --region)
      [[ $# -ge 2 ]] || { echo "Error: --region requires a value" >&2; usage 1; }
      REGION="$2"; shift 2 ;;
    --namespace)
      [[ $# -ge 2 ]] || { echo "Error: --namespace requires a value" >&2; usage 1; }
      NAMESPACE="$2"; shift 2 ;;
    --chart-version)
      [[ $# -ge 2 ]] || { echo "Error: --chart-version requires a value" >&2; usage 1; }
      CHART_VERSION="$2"; shift 2 ;;
    --app-version)
      [[ $# -ge 2 ]] || { echo "Error: --app-version requires a value" >&2; usage 1; }
      APP_VERSION="$2"; shift 2 ;;
    -h|--help)
      usage 0 ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      usage 1 ;;
  esac
done

if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "Error: --cluster-name is required (e.g. petclinic-dev)" >&2
  usage 1
fi

for cmd in kubectl helm aws; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: '${cmd}' is required but not found on PATH" >&2
    exit 1
  fi
done

echo "==> AWS Load Balancer Controller install plan"
echo "    cluster:        ${CLUSTER_NAME} (${REGION})"
echo "    namespace:      ${NAMESPACE}"
echo "    chart version:  ${CHART_VERSION} (Helm chart, eks.amazonaws.com/charts)"
echo "    app version:    ${APP_VERSION} (controller Git tag — source of the CRDs)"

# --- Resolve the IRSA role ARN (technical-spec.md → IRSA Roles) ----------------
if [[ -z "${ROLE_ARN}" ]]; then
  # petclinic-{env}-lb-controller-role with {env} == the cluster-name suffix
  # (cluster petclinic-dev → role petclinic-dev-lb-controller-role).
  ROLE_NAME="${CLUSTER_NAME}-lb-controller-role"
  echo "==> Looking up IRSA role ${ROLE_NAME}"
  ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" \
    --query 'Role.Arn' --output text 2>/dev/null || true)
  if [[ -z "${ROLE_ARN}" || "${ROLE_ARN}" == "None" ]]; then
    echo "Error: IAM role '${ROLE_NAME}' not found. Apply Terraform first" >&2
    echo "       (e.g. terraform -chdir=terraform/environments/dev apply) or pass --role-arn." >&2
    exit 1
  fi
fi
echo "    role ARN:       ${ROLE_ARN}"

# --- Sanity check: kubectl points somewhere ------------------------------------
CURRENT_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)
echo "==> kubectl API endpoint: ${CURRENT_SERVER:-<not configured>}"

# --- 1) CRDs, fetched from the controller repo at the APP version tag -----------
CRD_BASE_URL="https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${APP_VERSION}/config/crd"
echo "==> Installing CRDs from ${CRD_BASE_URL}/bases"
# Core ELB CRDs shipped by the chart for v3.x (fail hard if the tag is wrong —
# a wrong tag returns 404, which is exactly how a version mismatch shows up).
for crd in \
  elbv2.k8s.aws_targetgroupbindings.yaml \
  elbv2.k8s.aws_ingressclassparams.yaml \
  elbv2.k8s.aws_albtargetcontrolconfigs.yaml
do
  echo "    - ${crd}"
  kubectl apply -f "${CRD_BASE_URL}/bases/${crd}"
done

# Gateway API CRDs (controller v3 reconciles Gateway resources by default;
# upstream release notes recommend applying these before the controller starts).
echo "==> Installing Gateway API CRDs (gateway/gateway-crds.yaml)"
if ! kubectl apply -f "${CRD_BASE_URL}/gateway/gateway-crds.yaml"; then
  echo "    WARNING: could not apply gateway-crds.yaml for tag ${APP_VERSION}." >&2
  echo "             Fine for Ingress-only use on older v2.x tags; required for v3.x." >&2
fi

# --- 2) Helm repo ---------------------------------------------------------------
echo "==> Adding/updating the eks Helm repo (https://eks.amazonaws.com/charts)"
helm repo add eks https://eks.amazonaws.com/charts --force-update
helm repo update eks

# --- 3) helm upgrade --install --------------------------------------------------
# Values go into a generated file rather than --set flags: the role-arn
# annotation key contains dots that would otherwise need escaping, and the
# generated file is easy to inspect.
VALUES_FILE=$(mktemp)
trap 'rm -f "${VALUES_FILE}"' EXIT
cat > "${VALUES_FILE}" <<EOF
# Generated by scripts/install-lb-controller.sh — do not edit.
clusterName: ${CLUSTER_NAME}
region: ${REGION}
serviceAccount:
  create: true
  name: ${SERVICE_ACCOUNT}
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
EOF

echo "==> Installing/upgrading ${RELEASE_NAME} (CRDs already applied above → --skip-crds)"
helm upgrade --install "${RELEASE_NAME}" eks/aws-load-balancer-controller \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  --skip-crds \
  --wait \
  --timeout "${WAIT_TIMEOUT:-5m}"

# --- 4) IngressClass + verification (PETPLAT-29 acceptance criteria) ------------
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INGRESS_DIR="${REPO_ROOT}/k8s/base/ingress"
if [[ -f "${INGRESS_DIR}/ingressclass.yaml" ]]; then
  echo "==> Applying IngressClass manifest (${INGRESS_DIR}/ingressclass.yaml)"
  kubectl apply -f "${INGRESS_DIR}/ingressclass.yaml"
else
  echo "==> Skipping IngressClass manifest (not found: ${INGRESS_DIR}/ingressclass.yaml)"
fi

echo "==> Waiting for controller rollout"
kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE_NAME}" --timeout=180s

echo "==> Verifying"
kubectl get deployment "${RELEASE_NAME}" -n "${NAMESPACE}"
kubectl get ingressclass alb 2>/dev/null || echo "    (IngressClass 'alb' not found — check the apply above)"

cat <<EOF

AWS Load Balancer Controller is installed and healthy.

Next steps:
  1. Set the ACM certificate ARN in k8s/base/ingress/ingress.yaml:
       terraform -chdir=terraform/environments/dev output -raw dns_certificate_arn
  2. kubectl apply -f k8s/base/ingress/ingress.yaml   # controller creates the ALB
  3. PETPLAT-31 — point DNS at the ALB: get its endpoint
       kubectl -n petclinic-dev get ingress api-gateway \
         -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
     then set alb_dns_name + alb_hosted_zone_id in
     terraform/environments/dev/terraform.tfvars and run terraform apply.
  4. Verify: curl -I http://petclinic-dev.estherquispe.click   # 301 redirect
     curl -I https://petclinic-dev.estherquispe.click          # ALB answers
EOF

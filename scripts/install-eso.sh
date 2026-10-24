#!/bin/bash
# Install External Secrets Operator (ESO) on EKS — PETPLAT-34.
#
# Installs the ESO Helm chart (CRDs + controller) into the external-secrets
# namespace and applies the petclinic ClusterSecretStore + ExternalSecrets.
#
# Prerequisites: kubectl configured against the cluster, Helm 3+.
#
# After this script, annotate the ESO ServiceAccount with the IRSA role ARN
# created by Terraform (PETPLAT-37), one of:
#
#   ROLE_ARN=$(terraform output -raw eso_role_arn)   # run in terraform/environments/{dev,prod}
#   kubectl annotate sa external-secrets-sa -n external-secrets \
#     eks.amazonaws.com/role-arn="${ROLE_ARN}" --overwrite
#
# How to add a new secret:
#   1. Create it in AWS Secrets Manager (name: petclinic/{env}/<name>) — via
#      the terraform/modules/secrets module for non-RDS secrets (PETPLAT-33).
#   2. Add an ExternalSecret CR under k8s/base/external-secrets/ referencing
#      secretStoreRef aws-secrets-manager (kind: ClusterSecretStore).
#   3. kubectl apply -f k8s/base/external-secrets/<new-secret>.yaml
#
set -e

NAMESPACE="external-secrets"
RELEASE="external-secrets"

echo "=== External Secrets Operator installation for Petclinic ==="

# 1. Install ESO controller (Helm chart installs CRDs + controller).
echo "Installing ESO controller via Helm into namespace ${NAMESPACE}..."
helm repo add external-secrets https://kubernetes-sigs.external-secrets.io/charts/ 2>/dev/null || true
helm repo update
helm upgrade --install "${RELEASE}" external-secrets/external-secrets \
  --namespace "${NAMESPACE}" --create-namespace \
  --set installCRDs=true \
  --set crds.createClusterSecretStore=true \
  --set env[0].name=AWS_REGION \
  --set env[0].value=us-east-1 \
  --set env[1].name=POD_NAMESPACE \
  --set env[1].value="${NAMESPACE}" \
  --wait=false

# 2. Wait for ESO CRDs to be established in the API server.
# Helm installs the CRDs but returns before they are "Established".
# Use --wait=false to avoid Helm blocking on the webhook cert-controller;
# we wait for CRDs explicitly below instead.
echo "Waiting for ESO CRDs to be established..."
CRDS_TO_WAIT=()
for crd in clustersecretstores.external-secrets.io externalsecrets.external-secrets.io secretstores.external-secrets.io; do
  if kubectl get crd "${crd}" >/dev/null 2>&1; then
    CRDS_TO_WAIT+=("crd/${crd}")
  else
    echo "WARNING: CRD ${crd} not found after Helm install."
  fi
done

# If clustersecretstores is missing, force-enable it via helm upgrade.
if ! kubectl get crd clustersecretstores.external-secrets.io >/dev/null 2>&1; then
  echo "ClusterSecretStore CRD missing; retrying Helm install with crds.createClusterSecretStore=true..."
  helm upgrade "${RELEASE}" external-secrets/external-secrets \
    --namespace "${NAMESPACE}" \
    --set installCRDs=true \
    --set crds.createClusterSecretStore=true \
    --reuse-values \
    --wait=false
  # Re-check which CRDs exist
  CRDS_TO_WAIT=()
  for crd in clustersecretstores.external-secrets.io externalsecrets.external-secrets.io secretstores.external-secrets.io; do
    if kubectl get crd "${crd}" >/dev/null 2>&1; then
      CRDS_TO_WAIT+=("crd/${crd}")
    else
      echo "WARNING: CRD ${crd} still not found after helm upgrade."
    fi
  done
fi

if [ ${#CRDS_TO_WAIT[@]} -gt 0 ]; then
  kubectl wait --for=condition=Established "${CRDS_TO_WAIT[@]}" --timeout=120s || {
    echo "CRDs did not become established; retrying once after a short delay..."
    sleep 10
    kubectl wait --for=condition=Established "${CRDS_TO_WAIT[@]}" --timeout=120s
  }
else
  echo "ERROR: No ESO CRDs found. Helm chart may not have installed CRDs."
  exit 1
fi

# 3. Apply ClusterSecretStore and ExternalSecrets (CRDs now available).
echo "Applying ClusterSecretStore and ExternalSecrets..."
kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml
kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml
kubectl apply -f k8s/base/external-secrets/openai-api-key.yaml

echo "=== ESO installation complete ==="
echo "Verify: kubectl get pods -n ${NAMESPACE}"
echo "Verify: kubectl get clustersecretstore,externalsecrets -n ${NAMESPACE}"
echo "Remember: annotate external-secrets-sa with the IRSA role ARN (see header of this script)."

#!/usr/bin/env bash
set -euo pipefail

#
# build-push-images.sh — Build all 8 service images for ARM64 and push to ECR
# (PETPLAT-85 — initial manual build, before CI takes over).
#
# Maven builds the JARs ONLY (no buildDocker profile); docker buildx then
# builds each image for linux/arm64 (required for the t4g Graviton nodes) from
# the shared docker/Dockerfile in the application repo, tags it, and pushes it
# to {account}.dkr.ecr.{region}.amazonaws.com/petclinic-{env}/{service}:{tag}.
#
# Prerequisites:
#   - Application repo cloned NEXT TO this repo (or pass --app-repo):
#       ../spring-petclinic-microservices
#   - Java 17+ (Maven wrapper needs it), Docker with the buildx plugin
#   - AWS credentials with ECR push access (`aws sts get-caller-identity` works)
#   - ECR repos already applied: cd terraform/environments/dev && terraform apply
#
# Usage:
#   ./scripts/build-push-images.sh                              # dev, tag v1.0.0
#   ./scripts/build-push-images.sh --tag a1b2c3d                # short commit SHA
#   ./scripts/build-push-images.sh --env prod                   # prod repos
#   ./scripts/build-push-images.sh --app-repo /path/to/spring-petclinic-microservices
#   ./scripts/build-push-images.sh --skip-maven                 # reuse existing JARs
#   ./scripts/build-push-images.sh --with-tests                 # run tests in Maven build
#
# Reference — the equivalent manual commands (PETPLAT-85 documentation):
#   # 1. Build the JARs (from the application repo)
#   cd ../spring-petclinic-microservices && ./mvnw clean package -DskipTests
#
#   # 2. Login to ECR
#   ./scripts/ecr-login.sh --region us-east-1
#
#   # 3. Build + push one image (repeat for each service)
#   docker buildx build --platform linux/arm64 \
#     --build-arg ARTIFACT_NAME=spring-petclinic-config-server-<version> \
#     --build-arg EXPOSED_PORT=8888 \
#     -f ../spring-petclinic-microservices/docker/Dockerfile \
#     -t {account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/config-server:v1.0.0 \
#     --push ../spring-petclinic-microservices/spring-petclinic-config-server/target
#

ENV="dev"
TAG="v1.0.0"
REGION="us-east-1"
APP_REPO=""
SKIP_MAVEN=false
WITH_TESTS=false

# All 8 services (PETPLAT-20) → Maven module = spring-petclinic-{service}.
SERVICES="config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server"

usage() {
  echo "Usage: $0 [options]"
  echo "  --env <dev|prod>     Target environment (default: dev)"
  echo "  --tag <tag>          Image tag for all images (default: v1.0.0; 'latest' is not allowed)"
  echo "  --region <region>    AWS region of the ECR registry (default: us-east-1)"
  echo "  --app-repo <path>    Path to the spring-petclinic-microservices clone"
  echo "                       (default: <repo>/../spring-petclinic-microservices)"
  echo "  --skip-maven         Reuse JARs from a previous Maven build"
  echo "  --with-tests         Run unit tests during the Maven build (default: skipped)"
  echo "  -h, --help           Show this help"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -lt 2 ]] && { echo "Error: --env requires a value"; usage; }
      ENV="$2"; shift 2 ;;
    --tag)
      [[ $# -lt 2 ]] && { echo "Error: --tag requires a value"; usage; }
      TAG="$2"; shift 2 ;;
    --region)
      [[ $# -lt 2 ]] && { echo "Error: --region requires a value"; usage; }
      REGION="$2"; shift 2 ;;
    --app-repo)
      [[ $# -lt 2 ]] && { echo "Error: --app-repo requires a value"; usage; }
      APP_REPO="$2"; shift 2 ;;
    --skip-maven)
      SKIP_MAVEN=true; shift ;;
    --with-tests)
      WITH_TESTS=true; shift ;;
    -h|--help)
      usage ;;
    *)
      echo "Error: unknown argument '$1'"; usage ;;
  esac
done

# --- Input validation ---
if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "Error: --env must be 'dev' or 'prod' (got '${ENV}')"
  exit 1
fi
if [[ "${TAG}" == "latest" ]]; then
  echo "Error: the 'latest' tag is never used (technical-spec.md → Image Tag Strategy)."
  echo "Use a semantic version (v1.0.0) or a short commit SHA (e.g. a1b2c3d)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${APP_REPO}" ]]; then
  APP_REPO="${REPO_ROOT}/../spring-petclinic-microservices"
fi
if [[ ! -f "${APP_REPO}/mvnw" || ! -f "${APP_REPO}/docker/Dockerfile" ]]; then
  echo "Error: application repo not found at ${APP_REPO}"
  echo "Clone https://github.com/spring-petclinic/spring-petclinic-microservices next to this"
  echo "repo, or pass --app-repo <path>."
  exit 1
fi

# --- Resolve AWS account ID and registry ---
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
if [[ -z "${ACCOUNT_ID}" || "${ACCOUNT_ID}" == "None" ]]; then
  echo "Error: unable to resolve AWS account ID. Check your credentials."
  exit 1
fi
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Service port for the Dockerfile EXPOSED_PORT build arg — from the Service
# Inventory (technical-spec.md), NOT the incorrect docker.image.exposed.port
# values in several pom.xml files.
service_port() {
  case "$1" in
    config-server)     echo "8888" ;;
    discovery-server)  echo "8761" ;;
    api-gateway)       echo "8080" ;;
    customers-service) echo "8081" ;;
    visits-service)    echo "8082" ;;
    vets-service)      echo "8083" ;;
    genai-service)     echo "8084" ;;
    admin-server)      echo "9090" ;;
    *)                 echo "Error: unknown service '$1'" >&2; return 1 ;;
  esac
}

echo "============================================"
echo "  Building & pushing images to ECR"
echo "  Environment: ${ENV}  (petclinic-${ENV}/)"
echo "  Tag:         ${TAG}"
echo "  Registry:    ${REGISTRY}"
echo "  Platform:    linux/arm64 (Graviton t4g)"
echo "  App repo:    ${APP_REPO}"
echo "============================================"
echo ""

# --- Step 1: Maven builds the JARs (image creation is done by buildx) ---
if [[ "${SKIP_MAVEN}" == "true" ]]; then
  echo "[1/5] Skipping Maven build (--skip-maven) — reusing existing JARs."
else
  if ! command -v java >/dev/null 2>&1; then
    echo "Error: Java not found. Install Java 17+ (or set JAVA_HOME) to run ./mvnw."
    exit 1
  fi
  MVN_ARGS="clean package"
  if [[ "${WITH_TESTS}" == "false" ]]; then
    MVN_ARGS="${MVN_ARGS} -DskipTests"
  fi
  echo "[1/5] Building JARs: ./mvnw ${MVN_ARGS}"
  (cd "${APP_REPO}" && ./mvnw ${MVN_ARGS})
fi
echo ""

# --- Step 2: Authenticate Docker to ECR (PETPLAT-21) ---
echo "[2/5] Logging in to ECR..."
"${SCRIPT_DIR}/ecr-login.sh" --region "${REGION}"
echo ""

# --- Step 3: Preflight — fail fast if the ECR repos are not applied yet ---
echo "[3/5] Checking ECR repositories exist..."
for SERVICE in ${SERVICES}; do
  REPO_NAME="petclinic-${ENV}/${SERVICE}"
  if ! aws ecr describe-repositories \
      --repository-names "${REPO_NAME}" \
      --region "${REGION}" \
      --query 'repositories[0].repositoryName' \
      --output text >/dev/null 2>&1; then
    echo "Error: ECR repository '${REPO_NAME}' not found in ${REGION}."
    echo "Apply it first:"
    echo "  cd terraform/environments/${ENV} && terraform init && terraform plan && terraform apply"
    exit 1
  fi
  echo "  OK: ${REPO_NAME}"
done
echo ""

# --- Step 4: Prepare a buildx builder (QEMU binfmt needed on x86 hosts) ---
echo "[4/5] Preparing docker buildx builder 'petclinic-buildx'..."
HOST_ARCH="$(uname -m)"
if [[ "${HOST_ARCH}" != "aarch64" && "${HOST_ARCH}" != "arm64" ]]; then
  echo "  Host is ${HOST_ARCH} — installing QEMU binfmt for linux/arm64 emulation..."
  docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null
fi
if ! docker buildx inspect --builder petclinic-buildx >/dev/null 2>&1; then
  docker buildx create --name petclinic-buildx --driver docker-container >/dev/null
fi
docker buildx inspect --builder petclinic-buildx >/dev/null
echo "  Builder ready."
echo ""

# --- Step 5: Build (buildx, linux/arm64) and push each service image ---
echo "[5/5] Building and pushing 8 images..."
PUSHED_IMAGES=""
for SERVICE in ${SERVICES}; do
  MODULE="spring-petclinic-${SERVICE}"
  TARGET_DIR="${APP_REPO}/${MODULE}/target"

  # Locate the Spring Boot executable JAR (exclude the .jar.original backup).
  JAR=$(find "${TARGET_DIR}" -maxdepth 1 -name "${MODULE}-*.jar" ! -name "*.original" 2>/dev/null | head -n 1 || true)
  if [[ -z "${JAR}" ]]; then
    echo "Error: no JAR found for ${MODULE} in ${TARGET_DIR}."
    echo "Run without --skip-maven so ./mvnw can build the artifacts."
    exit 1
  fi
  ARTIFACT_NAME="$(basename "${JAR}" .jar)"
  PORT="$(service_port "${SERVICE}")"
  IMAGE="${REGISTRY}/petclinic-${ENV}/${SERVICE}:${TAG}"

  echo "--- ${SERVICE}: ${IMAGE}"
  echo "    artifact=${ARTIFACT_NAME}  port=${PORT}"
  docker buildx build \
    --builder petclinic-buildx \
    --platform linux/arm64 \
    --build-arg ARTIFACT_NAME="${ARTIFACT_NAME}" \
    --build-arg EXPOSED_PORT="${PORT}" \
    -f "${APP_REPO}/docker/Dockerfile" \
    -t "${IMAGE}" \
    --push \
    "${TARGET_DIR}"

  PUSHED_IMAGES="${PUSHED_IMAGES}  ${IMAGE}"$'\n'
done
echo ""

# --- Verify the pushed images are visible in ECR ---
echo "Verifying images in ECR..."
for SERVICE in ${SERVICES}; do
  DIGEST=$(aws ecr describe-images \
    --repository-name "petclinic-${ENV}/${SERVICE}" \
    --image-ids "imageTag=${TAG}" \
    --region "${REGION}" \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>/dev/null || echo "NOT_FOUND")
  if [[ "${DIGEST}" == "NOT_FOUND" || "${DIGEST}" == "None" ]]; then
    echo "  FAIL: petclinic-${ENV}/${SERVICE}:${TAG} not found in ECR"
    exit 1
  fi
  echo "  OK: petclinic-${ENV}/${SERVICE}:${TAG} (${DIGEST})"
done

echo ""
echo "============================================"
echo "  All 8 images pushed successfully:"
printf "%s" "${PUSHED_IMAGES}"
echo "============================================"



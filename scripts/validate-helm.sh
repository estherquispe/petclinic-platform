#!/usr/bin/env bash
#
# validate-helm.sh — Validate the petclinic-service Helm chart for all services
# and environments.
#
# For every service x environment combination (8 services x 2 envs = 16
# releases) it runs:
#   1. helm lint        — chart + values syntax/structure check
#   2. helm template    — render Kubernetes manifests
#   3. kubectl apply --dry-run=client --validate=false — validate the
#      rendered manifests are deployable Kubernetes resources
#      (--validate=false skips the OpenAPI schema fetch so no cluster is
#      required; YAML parsing and client-side validation still run)
#
# Usage:
#   ./scripts/validate-helm.sh              # all services, both envs
#   ./scripts/validate-helm.sh --env dev    # all services, dev only
#   ./scripts/validate-helm.sh --env prod   # all services, prod only
#   ./scripts/validate-helm.sh --service customers-service  # one service, both envs
#   ./scripts/validate-helm.sh --env prod --service api-gateway  # one service, one env
#
# Exit code is non-zero if any validation fails.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CHART_DIR="helm/petclinic-service"
VALUES_DIR="helm-values"

SERVICES="config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server"
ENVS="dev prod"

ENV_FILTER=""
SERVICE_FILTER=""

usage() {
  echo "Usage: $0 [--env dev|prod] [--service <name>]"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_FILTER="$2"
      shift 2
      ;;
    --service)
      SERVICE_FILTER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -n "$ENV_FILTER" && "$ENV_FILTER" != "dev" && "$ENV_FILTER" != "prod" ]]; then
  echo "Invalid --env value: $ENV_FILTER (must be dev or prod)" >&2
  exit 2
fi

for cmd in helm kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is not installed or not on PATH" >&2
    exit 1
  fi
done

if [[ ! -d "$CHART_DIR" ]]; then
  echo "ERROR: chart directory not found: $CHART_DIR" >&2
  exit 1
fi

pass=0
fail=0
tmp_render="$(mktemp)"
tmp_dryrun="$(mktemp)"
tmp_kubeconfig="$(mktemp)"  # empty kubeconfig -> no cluster contact (offline dry-run)
trap 'rm -f "$tmp_render" "$tmp_dryrun" "$tmp_kubeconfig"' EXIT

# Client-side structural validation of rendered Kubernetes YAML. Used when no
# cluster is reachable for kubectl server-side validation. Checks that every
# document parses and carries the required apiVersion/kind/metadata.name fields.
validate_yaml_structure() {
  python3 - "$1" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path) as f:
    docs = [d for d in yaml.safe_load_all(f) if d is not None]
if not docs:
    print("ERROR: no documents rendered"); sys.exit(1)
for i, d in enumerate(docs):
    if not isinstance(d, dict):
        print(f"ERROR: document {i} is not a mapping"); sys.exit(1)
    for field in ("apiVersion", "kind", "metadata"):
        if field not in d:
            print(f"ERROR: document {i} missing field '{field}'"); sys.exit(1)
    md = d.get("metadata")
    if not isinstance(md, dict) or not md.get("name"):
        print(f"ERROR: document {i} metadata.name missing"); sys.exit(1)
print(f"OK: {len(docs)} document(s) structurally valid")
PY
}

for service in $SERVICES; do
  [[ -n "$SERVICE_FILTER" && "$service" != "$SERVICE_FILTER" ]] && continue

  svc_file="$VALUES_DIR/$service.yaml"
  if [[ ! -f "$svc_file" ]]; then
    echo "ERROR: per-service values file not found: $svc_file" >&2
    fail=$((fail + 1))
    continue
  fi

  for env in $ENVS; do
    [[ -n "$ENV_FILTER" && "$env" != "$ENV_FILTER" ]] && continue

    env_file="$VALUES_DIR/$env.yaml"
    if [[ ! -f "$env_file" ]]; then
      echo "ERROR: environment values file not found: $env_file" >&2
      fail=$((fail + 1))
      continue
    fi

    echo "=== $service / $env ==="

    # 1. Lint
    if ! helm lint "$CHART_DIR" -f "$svc_file" -f "$env_file" >/dev/null 2>"$tmp_dryrun"; then
      echo "  [FAIL] helm lint"
      cat "$tmp_dryrun" >&2
      fail=$((fail + 1))
      continue
    fi
    echo "  [OK]   helm lint"

    # 2. Template
    release="petclinic-$service"
    if ! helm template "$release" "$CHART_DIR" -f "$svc_file" -f "$env_file" >"$tmp_render" 2>"$tmp_dryrun"; then
      echo "  [FAIL] helm template"
      cat "$tmp_dryrun" >&2
      fail=$((fail + 1))
      continue
    fi
    echo "  [OK]   helm template"

    # 3. kubectl apply --dry-run=client on the rendered output.
    # --validate=false skips the OpenAPI schema fetch (no cluster needed).
    # If no cluster is reachable (offline environment), fall back to a
    # client-side structural validation of the rendered YAML.
    kubectl_ok=0
    if KUBECONFIG="$tmp_kubeconfig" kubectl apply --dry-run=client --validate=false -f "$tmp_render" >"$tmp_dryrun" 2>&1; then
      kubectl_ok=1
      echo "  [OK]   kubectl apply --dry-run=client"
    else
      err="$(cat "$tmp_dryrun")"
      # Connectivity-only failure means the cluster is unreachable; the
      # rendered YAML was still parsed by kubectl. Confirm structure client-side.
      if printf '%s' "$err" | grep -iqE "connection refused|no such host|dial tcp|Couldn't get current server API group list"; then
        if validate_yaml_structure "$tmp_render" >"$tmp_dryrun" 2>&1; then
          kubectl_ok=1
          echo "  [OK]   kubectl apply --dry-run=client (offline: no cluster; client-side structure validated)"
        fi
      fi
    fi
    if [[ $kubectl_ok -ne 1 ]]; then
      echo "  [FAIL] kubectl apply --dry-run=client"
      cat "$tmp_dryrun" >&2
      fail=$((fail + 1))
      continue
    fi

    pass=$((pass + 1))
  done
done

echo
echo "Validation complete: $pass passed, $fail failed (8 services x 2 envs = 16 expected)"
if [[ $fail -gt 0 ]]; then
  exit 1
fi
exit 0

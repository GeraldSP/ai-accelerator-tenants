#!/usr/bin/env bash
# Override nemoclaw-inference from gitignored inference.env (optional).
# Default in-cluster secret is Argo-synced from inference-incluster.env.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="${ROOT}/namespaces/base/secrets"
ENV_FILE="${SECRETS_DIR}/inference.env"
EXAMPLE="${SECRETS_DIR}/inference.env.example"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  echo "Only needed to override the Argo-synced in-cluster defaults." >&2
  echo "  cp ${EXAMPLE} ${ENV_FILE}" >&2
  exit 1
fi

if ! grep -qE '^NEMOCLAW_INFERENCE_BASE_URL=.' "${ENV_FILE}"; then
  echo "NEMOCLAW_INFERENCE_BASE_URL is empty in ${ENV_FILE}" >&2
  exit 1
fi

echo "Applying nemoclaw-inference override to namespace openshell from ${ENV_FILE}"
oc -n openshell create secret generic nemoclaw-inference \
  --from-env-file="${ENV_FILE}" \
  --dry-run=client -o yaml | oc apply -f -
echo "Done."

#!/usr/bin/env bash
# Apply hf-secret from the gitignored hf-token.env (not synced by Argo CD).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="${ROOT}/namespaces/base/secrets"
ENV_FILE="${SECRETS_DIR}/hf-token.env"
EXAMPLE="${SECRETS_DIR}/hf-token.env.example"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  echo "Copy the example and set HF_TOKEN:" >&2
  echo "  cp ${EXAMPLE} ${ENV_FILE}" >&2
  exit 1
fi

if grep -qE '^HF_TOKEN=$|^HF_TOKEN=\s*$' "${ENV_FILE}" || ! grep -qE '^HF_TOKEN=.' "${ENV_FILE}"; then
  echo "HF_TOKEN is empty in ${ENV_FILE}" >&2
  exit 1
fi

echo "Applying hf-secret to namespace helpdesk-email-triage from gitignored env file"
kustomize build "${SECRETS_DIR}" | oc apply -f -
echo "Done."

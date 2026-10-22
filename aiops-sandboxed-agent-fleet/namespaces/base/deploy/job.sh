#!/usr/bin/env bash
# Clone upstream aiops-sandboxed-agent-fleet at a pinned commit and run deploy.sh.
# Requires cluster-admin-equivalent RBAC (operators, CRDs, multi-ns Helm).
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/rh-ai-quickstart/aiops-sandboxed-agent-fleet.git}"
UPSTREAM_REF="${UPSTREAM_REF:-90e7d60155b6f28fccab0658ca3c5b1f3f920d92}"
WORK_DIR="${WORK_DIR:-/tmp/aiops-sandboxed-agent-fleet}"
SECRET_NS="${SECRET_NS:-openshell}"
INFERENCE_SECRET="${INFERENCE_SECRET:-nemoclaw-inference}"
GHCR_SECRET="${GHCR_SECRET:-nemoclaw-ghcr}"

log()  { printf '[aiops-deploy] %s\n' "$*"; }
die()  { printf '[aiops-deploy] ERROR: %s\n' "$*" >&2; exit 1; }

install_tools() {
  log "Installing helm, yq, jq, git, gettext (envsubst)"
  # helm
  if ! command -v helm >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  # yq (mikefarah)
  if ! command -v yq >/dev/null 2>&1; then
    curl -fsSL -o /usr/local/bin/yq \
      https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64
    chmod +x /usr/local/bin/yq
  fi
  # jq + git + envsubst (gettext)
  if command -v microdnf >/dev/null 2>&1; then
    microdnf install -y jq git gettext >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq git gettext >/dev/null
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq git gettext >/dev/null
  else
    die "No package manager to install jq/git/gettext"
  fi
  command -v oc >/dev/null 2>&1 || die "oc not found"
  command -v helm >/dev/null 2>&1 || die "helm not found"
  command -v yq >/dev/null 2>&1 || die "yq not found"
  command -v jq >/dev/null 2>&1 || die "jq not found"
  command -v envsubst >/dev/null 2>&1 || die "envsubst not found"
  command -v git >/dev/null 2>&1 || die "git not found"
}

secret_to_env() {
  local ns="$1" name="$2" out="$3"
  local key b64 val
  if ! oc -n "${ns}" get secret "${name}" >/dev/null 2>&1; then
    log "Secret ${ns}/${name} not found — deploy will proceed unconfigured for missing keys"
    return 0
  fi
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    b64="$(oc -n "${ns}" get secret "${name}" -o "jsonpath={.data.${key}}")"
    [[ -n "${b64}" ]] || continue
    val="$(printf '%s' "${b64}" | base64 -d 2>/dev/null || true)"
    # Escape for dotenv-style sourcing by deploy.sh load_env
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    printf '%s="%s"\n' "${key}" "${val}" >> "${out}"
  done < <(oc -n "${ns}" get secret "${name}" -o json | jq -r '.data // {} | keys[]')
  log "Merged keys from secret ${ns}/${name} into ${out}"
}

clone_upstream() {
  rm -rf "${WORK_DIR}"
  mkdir -p "${WORK_DIR}"
  log "Cloning ${UPSTREAM_REPO} @ ${UPSTREAM_REF}"
  git -C "${WORK_DIR}" init
  git -C "${WORK_DIR}" remote add origin "${UPSTREAM_REPO}"
  # Fetch the pinned commit (GitHub allows fetch-by-SHA)
  git -C "${WORK_DIR}" fetch --depth 1 origin "${UPSTREAM_REF}"
  git -C "${WORK_DIR}" checkout FETCH_HEAD
}

# quay.io/minio/* is no longer anonymously pullable (401).
# Use public coollabsio MinIO image (includes minio server + mc + /bin/sh).
patch_minio_images() {
  local minio_img="${MINIO_IMAGE:-ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z}"
  local mc_img="${MINIO_MC_IMAGE:-ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z}"
  local dep="${WORK_DIR}/deploy/observability/minio/templates/deployment.yaml"
  local init="${WORK_DIR}/deploy/observability/minio/templates/bucket-init-job.yaml"
  [[ -f "${dep}" ]] || die "missing ${dep}"
  [[ -f "${init}" ]] || die "missing ${init}"
  log "Replacing non-public quay.io/minio images with ${minio_img}"
  sed -i.bak \
    -e "s|image: quay.io/minio/minio:.*|image: ${minio_img}|" \
    "${dep}"
  sed -i.bak \
    -e "s|image: quay.io/minio/mc:.*|image: ${mc_img}|" \
    "${init}"
  rm -f "${dep}.bak" "${init}.bak"
  grep -n 'image:' "${dep}" "${init}" || true
}

write_dotenv() {
  local env_file="${WORK_DIR}/.env"
  : > "${env_file}"
  secret_to_env "${SECRET_NS}" "${INFERENCE_SECRET}" "${env_file}"
  secret_to_env "${SECRET_NS}" "${GHCR_SECRET}" "${env_file}"
  # Sensible defaults when secret omitted keys
  grep -q '^DEPLOY_DEMO_APP=' "${env_file}" 2>/dev/null || echo 'DEPLOY_DEMO_APP="true"' >> "${env_file}"
  grep -q '^PROVISION_AGENT=' "${env_file}" 2>/dev/null || echo 'PROVISION_AGENT="false"' >> "${env_file}"
  log "Wrote ${env_file}"
}

# A killed/retried deploy Job leaves Helm releases in pending-install/upgrade,
# so the next run fails with "another operation is in progress".
clear_stuck_helm_releases() {
  local ns release status
  for ns_release in "monitoring:nemoclaw-monitoring" "openshell:nemoclaw"; do
    ns="${ns_release%%:*}"
    release="${ns_release##*:}"
    status="$(helm -n "${ns}" status "${release}" -o json 2>/dev/null | jq -r '.info.status // empty' || true)"
    case "${status}" in
      pending-install|pending-upgrade|pending-rollback)
        log "Clearing stuck Helm release ${ns}/${release} (status=${status})"
        helm -n "${ns}" uninstall "${release}" --wait --timeout 3m || \
          oc -n "${ns}" delete secret -l "name=${release},owner=helm,status=${status}" --ignore-not-found
        ;;
      *)
        log "Helm ${ns}/${release}: ${status:-absent}"
        ;;
    esac
  done
}

main() {
  install_tools
  clear_stuck_helm_releases
  clone_upstream
  patch_minio_images
  write_dotenv
  log "Running upstream deploy.sh (operators + Helm + demo app + fleet)"
  cd "${WORK_DIR}"
  chmod +x scripts/*.sh scripts/lib/*.sh 2>/dev/null || true
  ./scripts/deploy.sh
  log "Deploy finished"
}

main "$@"

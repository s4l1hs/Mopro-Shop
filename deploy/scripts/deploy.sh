#!/usr/bin/env bash
# deploy/scripts/deploy.sh — Production deploy to Mopro VDS.
# Usage: ./deploy/scripts/deploy.sh <version>
# Called by: make deploy VERSION=<ver> SERVER=mopro@195.85.207.92
#
# Flow:
#   1. scp tarballs from local bin/ to VDS /opt/mopro/bin/
#   2. docker load each image on VDS
#   3. Rolling restart: jobs-svc → core-svc → fin-svc
#   4. Health check each service; auto-rollback if any /healthz ≠ 200
set -euo pipefail

VERSION="${1:?Usage: deploy.sh <version>}"
SERVER="${SERVER:-mopro@195.85.207.92}"
SSH_PORT="${SSH_PORT:-4625}"
MOPRO_DIR="/opt/mopro"
BIN_DIR="${MOPRO_DIR}/bin"
COMPOSE="docker compose -f ${MOPRO_DIR}/docker-compose.prod.yml"
HEALTHZ_TIMEOUT=60  # seconds to wait for each service to become healthy

_ssh() { ssh -p "${SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER}" "$@"; }
_scp() { scp -P "${SSH_PORT}" "$@"; }

echo "═══════════════════════════════════════════════════════"
echo " Mopro deploy — version: ${VERSION}"
echo " Target: ${SERVER} (port ${SSH_PORT})"
echo "═══════════════════════════════════════════════════════"

# ── 1. Upload image tarballs ─────────────────────────────────────────────────
echo "[1/5] Uploading image tarballs..."
_scp \
  "bin/core-svc-${VERSION}.tar" \
  "bin/fin-svc-${VERSION}.tar" \
  "bin/jobs-svc-${VERSION}.tar" \
  "${SERVER}:${BIN_DIR}/"

# ── 2. Archive current images as prev/ ───────────────────────────────────────
echo "[2/5] Archiving previous images to ${BIN_DIR}/prev/..."
_ssh "
  for svc in core-svc fin-svc jobs-svc; do
    if [[ -f '${BIN_DIR}/'\${svc}'-current.tar' ]]; then
      cp '${BIN_DIR}/'\${svc}'-current.tar' '${BIN_DIR}/prev/'\${svc}'-prev.tar'
    fi
  done
  cp '${BIN_DIR}/core-svc-${VERSION}.tar'  '${BIN_DIR}/core-svc-current.tar'
  cp '${BIN_DIR}/fin-svc-${VERSION}.tar'   '${BIN_DIR}/fin-svc-current.tar'
  cp '${BIN_DIR}/jobs-svc-${VERSION}.tar'  '${BIN_DIR}/jobs-svc-current.tar'
"

# ── 3. Load images on VDS ─────────────────────────────────────────────────────
echo "[3/5] Loading Docker images on VDS..."
_ssh "
  docker load < '${BIN_DIR}/core-svc-${VERSION}.tar'
  docker load < '${BIN_DIR}/fin-svc-${VERSION}.tar'
  docker load < '${BIN_DIR}/jobs-svc-${VERSION}.tar'
  echo '  Images loaded'
"

# ── 4. Rolling restart: jobs → core → fin ────────────────────────────────────
echo "[4/5] Rolling restart (jobs-svc → core-svc → fin-svc)..."

_restart_and_check() {
  local svc="$1"
  echo "  Restarting ${svc}..."
  _ssh "
    cd '${MOPRO_DIR}'
    VERSION='${VERSION}' ${COMPOSE} up -d --no-deps '${svc}'
  "

  echo "  Waiting for ${svc} healthcheck (timeout ${HEALTHZ_TIMEOUT}s)..."
  local elapsed=0
  while true; do
    local status
    status=$(_ssh "docker inspect --format='{{.State.Health.Status}}' '${svc}' 2>/dev/null || echo 'missing'") || true
    if [[ "${status}" == "healthy" ]]; then
      echo "  ${svc}: healthy ✓"
      return 0
    fi
    if [[ "${elapsed}" -ge "${HEALTHZ_TIMEOUT}" ]]; then
      echo "  ERROR: ${svc} did not become healthy within ${HEALTHZ_TIMEOUT}s (status: ${status})" >&2
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

for svc in jobs-svc core-svc fin-svc; do
  if ! _restart_and_check "${svc}"; then
    echo ""
    echo "  !! Health check failed for ${svc} — triggering rollback" >&2
    "$(dirname "$0")/rollback.sh"
    exit 1
  fi
done

# ── 5. Reload Caddy (picks up any Caddyfile changes) ─────────────────────────
echo "[5/5] Reloading Caddy..."
_ssh "
  cd '${MOPRO_DIR}'
  ${COMPOSE} exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
"

echo ""
echo "════════════════════════════════════════════════════════"
echo " Deploy complete — ${VERSION}"
echo " Verify: curl -sf https://api.moproshop.com/healthz"
echo "════════════════════════════════════════════════════════"

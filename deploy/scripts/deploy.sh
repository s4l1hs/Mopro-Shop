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
COMPOSE="docker compose -f ${MOPRO_DIR}/deploy/docker-compose.prod.yml"
HEALTHZ_TIMEOUT=60  # seconds to wait for each service to return HTTP 200 on /healthz

_ssh() { ssh -p "${SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER}" "$@"; }
_scp() { scp -P "${SSH_PORT}" "$@"; }

_svc_port() {
  case "$1" in
    core-svc) echo 8080 ;;
    fin-svc)  echo 8081 ;;
    jobs-svc) echo 8082 ;;
  esac
}

echo "═══════════════════════════════════════════════════════"
echo " Mopro deploy — version: ${VERSION}"
echo " Target: ${SERVER} (port ${SSH_PORT})"
echo "═══════════════════════════════════════════════════════"

# ── 0. Sync deploy/ directory to VDS ─────────────────────────────────────────
echo "[0/5] Syncing deploy/ files to VDS..."
rsync -az --exclude='.env' \
  deploy/ "${SERVER}:${MOPRO_DIR}/deploy/"
_ssh "
  mkdir -p '${MOPRO_DIR}/deploy'
  if [[ ! -L '${MOPRO_DIR}/deploy/.env' ]] && [[ ! -f '${MOPRO_DIR}/deploy/.env' ]]; then
    ln -sf /etc/mopro/.env '${MOPRO_DIR}/deploy/.env'
  fi
"

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

# ── 3. Load images on VDS and tag :latest ─────────────────────────────────────
echo "[3/5] Loading Docker images on VDS..."
_ssh "
  docker load < '${BIN_DIR}/core-svc-${VERSION}.tar'
  docker tag mopro/core-svc:${VERSION} mopro/core-svc:latest
  docker load < '${BIN_DIR}/fin-svc-${VERSION}.tar'
  docker tag mopro/fin-svc:${VERSION} mopro/fin-svc:latest
  docker load < '${BIN_DIR}/jobs-svc-${VERSION}.tar'
  docker tag mopro/jobs-svc:${VERSION} mopro/jobs-svc:latest
  echo '  Images loaded and tagged :latest'
"

# Ensure all services are up (handles first deploy and Compose v5 quirk)
_ssh "
  VERSION='${VERSION}' ${COMPOSE} up -d
  VERSION='${VERSION}' ${COMPOSE} up -d
"

# ── 4. Rolling restart: jobs → core → fin ────────────────────────────────────
echo "[4/5] Rolling restart (jobs-svc → core-svc → fin-svc)..."

_restart_and_check() {
  local svc="$1"
  local port
  port=$(_svc_port "${svc}")

  echo "  Restarting ${svc}..."
  _ssh "
    VERSION='${VERSION}' ${COMPOSE} up -d --no-deps '${svc}'
  "

  echo "  Waiting for ${svc} /healthz on :${port} (timeout ${HEALTHZ_TIMEOUT}s)..."
  _ssh "
    elapsed=0
    while true; do
      cstate=\$(docker inspect --format='{{.State.Status}}' '${svc}' 2>/dev/null || echo missing)
      if [[ \"\${cstate}\" == 'exited' ]] || [[ \"\${cstate}\" == 'missing' ]]; then
        echo '  ERROR: ${svc} container is '\"\${cstate}\" >&2
        exit 1
      fi
      http=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${port}/healthz 2>/dev/null || echo 000)
      if [[ \"\${http}\" == '200' ]]; then
        echo '  ${svc}: healthy (HTTP 200) ✓'
        exit 0
      fi
      if [[ \"\${elapsed}\" -ge '${HEALTHZ_TIMEOUT}' ]]; then
        echo '  ERROR: ${svc} /healthz returned '\"\${http}\"' after ${HEALTHZ_TIMEOUT}s' >&2
        exit 1
      fi
      sleep 5
      elapsed=\$((elapsed + 5))
    done
  " || return 1
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
  ${COMPOSE} exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
"

echo ""
echo "════════════════════════════════════════════════════════"
echo " Deploy complete — ${VERSION}"
echo " Verify: curl -sf https://api.moproshop.com/healthz"
echo "════════════════════════════════════════════════════════"

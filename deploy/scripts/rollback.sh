#!/usr/bin/env bash
# deploy/scripts/rollback.sh — Restore previous image set on Mopro VDS.
# Usage: ./deploy/scripts/rollback.sh
# Called automatically by deploy.sh on health check failure, or manually.
set -euo pipefail

SERVER="${SERVER:-mopro@195.85.207.92}"
SSH_PORT="${SSH_PORT:-4625}"
MOPRO_DIR="/opt/mopro"
BIN_DIR="${MOPRO_DIR}/bin"
COMPOSE="docker compose -f ${MOPRO_DIR}/docker-compose.prod.yml"

_ssh() { ssh -p "${SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER}" "$@"; }

echo "═══════════════════════════════════════════════════════"
echo " Mopro rollback — restoring previous images"
echo " Target: ${SERVER} (port ${SSH_PORT})"
echo "═══════════════════════════════════════════════════════"

_ssh "
  set -euo pipefail
  for svc in core-svc fin-svc jobs-svc; do
    prev='${BIN_DIR}/prev/'\${svc}'-prev.tar'
    if [[ ! -f \"\${prev}\" ]]; then
      echo \"  WARNING: No previous image for \${svc} — skipping rollback for this service\"
      continue
    fi
    echo \"  Loading previous \${svc} image...\"
    docker load < \"\${prev}\"
  done

  cd '${MOPRO_DIR}'
  echo '  Restarting services with previous images...'
  ${COMPOSE} up -d --no-deps jobs-svc core-svc fin-svc

  echo '  Waiting 30s for services to stabilise...'
  sleep 30

  for svc in jobs-svc core-svc fin-svc; do
    status=\$(docker inspect --format='{{.State.Health.Status}}' \"\${svc}\" 2>/dev/null || echo 'missing')
    echo \"  \${svc}: \${status}\"
  done
"

echo ""
echo "════════════════════════════════════════════════════════"
echo " Rollback complete. Verify:"
echo "   curl -sf https://api.moproshop.com/healthz"
echo "════════════════════════════════════════════════════════"

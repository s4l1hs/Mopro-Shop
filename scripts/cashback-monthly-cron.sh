#!/usr/bin/env bash
# Triggers the cashback monthly cron inside fin-svc.
# Scheduled: 0 2 1 * * /opt/mopro/scripts/cashback-monthly-cron.sh
# fin-svc runs this automatically via its internal cron; this script is the external health-check wrapper.
set -euo pipefail

source /opt/mopro/.env 2>/dev/null || source "$(dirname "$0")/../.env" 2>/dev/null || true

log() { echo "[cashback-cron] $(date -u +%FT%TZ) $*"; }

PERIOD="$(date +%Y%m)"
log "triggering cashback monthly cron for period ${PERIOD}"

# TODO(mopro:placeholder): call fin-svc admin endpoint POST /internal/v1/cashback/run-monthly
# Unblocked by: Phase 3 (cashback engine implementation) and Phase 1 (fin-svc HTTP server)
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://localhost:8082/internal/v1/cashback/run-monthly" \
    -H "Authorization: Bearer ${ADMIN_INTERNAL_TOKEN:-}" \
    -H "Content-Type: application/json" \
    -d "{\"period\":\"${PERIOD}\"}" 2>/dev/null || echo "000")

if [ "${RESPONSE}" = "200" ]; then
    log "OK: cashback cron completed for ${PERIOD}"
    if [ -n "${HEALTHCHECK_CASHBACK_CRON_UUID:-}" ]; then
        curl -s --fail "https://hc-ping.com/${HEALTHCHECK_CASHBACK_CRON_UUID}" || true
    fi
else
    log "FAILED: fin-svc returned HTTP ${RESPONSE}"
    if [ -n "${HEALTHCHECK_CASHBACK_CRON_UUID:-}" ]; then
        curl -s --fail "https://hc-ping.com/${HEALTHCHECK_CASHBACK_CRON_UUID}/fail" || true
    fi
    exit 1
fi

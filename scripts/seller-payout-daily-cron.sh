#!/usr/bin/env bash
# Triggers the seller payout daily cron inside fin-svc.
# Scheduled: 30 2 * * * /opt/mopro/scripts/seller-payout-daily-cron.sh
# fin-svc runs this automatically via its internal cron; this script is the external health-check wrapper.
set -euo pipefail

source /opt/mopro/.env 2>/dev/null || source "$(dirname "$0")/../.env" 2>/dev/null || true

log() { echo "[payout-cron] $(date -u +%FT%TZ) $*"; }

TODAY="$(date +%Y-%m-%d)"
log "triggering seller payout daily cron for ${TODAY}"

# TODO(mopro:placeholder): call fin-svc admin endpoint POST /internal/v1/payout/run-daily
# Unblocked by: Phase 4 (seller payout engine) and Phase 1 (fin-svc HTTP server)
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://localhost:8082/internal/v1/payout/run-daily" \
    -H "Authorization: Bearer ${ADMIN_INTERNAL_TOKEN:-}" \
    -H "Content-Type: application/json" \
    -d "{\"date\":\"${TODAY}\"}" 2>/dev/null || echo "000")

if [ "${RESPONSE}" = "200" ]; then
    log "OK: payout cron completed for ${TODAY}"
    if [ -n "${HEALTHCHECK_SELLER_PAYOUT_CRON_UUID:-}" ]; then
        curl -s --fail "https://hc-ping.com/${HEALTHCHECK_SELLER_PAYOUT_CRON_UUID}" || true
    fi
else
    log "FAILED: fin-svc returned HTTP ${RESPONSE}"
    if [ -n "${HEALTHCHECK_SELLER_PAYOUT_CRON_UUID:-}" ]; then
        curl -s --fail "https://hc-ping.com/${HEALTHCHECK_SELLER_PAYOUT_CRON_UUID}/fail" || true
    fi
    exit 1
fi

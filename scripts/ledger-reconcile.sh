#!/usr/bin/env bash
# Hourly per-currency ledger reconciliation: Sum(D) - Sum(C) must equal 0 for each currency.
# Run hourly: 0 * * * * /opt/mopro/scripts/ledger-reconcile.sh
set -euo pipefail

source "$(dirname "$0")/../.env.local" 2>/dev/null || true

log() { echo "[ledger-reconcile] $(date -u +%FT%TZ) $*"; }

# TODO(mopro:placeholder): implement full SQL-based reconcile query against postgres-ledger
# Unblocked by: Phase 0.2 (ledger schema) and Phase 1 (DB connectivity in scripts)

QUERY="
SELECT currency, SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END) AS delta
FROM wallet_schema.ledger_entries
GROUP BY currency
HAVING ABS(SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END)) > 0;
"

RESULT=$(docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -t -c "${QUERY}" 2>/dev/null || echo "DB_UNAVAILABLE")

if [ "${RESULT}" = "DB_UNAVAILABLE" ]; then
    log "SKIP: postgres-ledger not reachable"
    exit 0
fi

if [ -n "$(echo "${RESULT}" | tr -d '[:space:]')" ]; then
    log "ALERT: ledger imbalance detected — ${RESULT}"
    if [ -n "${SLACK_PANIC_WEBHOOK:-}" ]; then
        curl -s -X POST "${SLACK_PANIC_WEBHOOK}" -H 'Content-type: application/json' \
            -d "{\"text\":\"MOPRO SEV1: ledger imbalance: ${RESULT}\"}" || true
    fi
    if [ -n "${HEALTHCHECK_LEDGER_RECONCILE_UUID:-}" ]; then
        curl -s --fail "https://hc-ping.com/${HEALTHCHECK_LEDGER_RECONCILE_UUID}/fail" || true
    fi
    exit 1
fi

log "OK: all currencies balanced"
if [ -n "${HEALTHCHECK_LEDGER_RECONCILE_UUID:-}" ]; then
    curl -s --fail "https://hc-ping.com/${HEALTHCHECK_LEDGER_RECONCILE_UUID}" || true
fi

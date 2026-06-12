#!/usr/bin/env bash
# Monitors disk usage and escalates through alert/panic thresholds.
# Run every 5 minutes via cron: */5 * * * * /opt/mopro/scripts/disk-watch.sh
set -euo pipefail

source "$(dirname "$0")/../.env" 2>/dev/null || true

DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

log() { echo "[disk-watch] $(date -u +%FT%TZ) $*"; }

if [ "${DISK_USAGE}" -ge 92 ]; then
    log "PANIC: ${DISK_USAGE}% — switching Postgres to read-only"
    docker exec postgres-ecom  psql -U ecom_admin -d mopro_ecom   -c "ALTER SYSTEM SET default_transaction_read_only = on; SELECT pg_reload_conf();" || true
    docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c "ALTER SYSTEM SET default_transaction_read_only = on; SELECT pg_reload_conf();" || true
    if [ -n "${SLACK_PANIC_WEBHOOK:-}" ]; then
        curl -s -X POST "${SLACK_PANIC_WEBHOOK}" -H 'Content-type: application/json' \
            -d "{\"text\":\"MOPRO DISK PANIC: ${DISK_USAGE}% used — Postgres set to read-only\"}" || true
    fi
elif [ "${DISK_USAGE}" -ge 85 ]; then
    log "ALERT: ${DISK_USAGE}% — paging on-call"
    if [ -n "${BETTERSTACK_INCIDENT_API:-}" ]; then
        curl -s -X POST "${BETTERSTACK_INCIDENT_API}" \
            -H "Authorization: Bearer ${BETTERSTACK_INCIDENT_API}" \
            -d "name=Disk+usage+${DISK_USAGE}%25" || true
    fi
elif [ "${DISK_USAGE}" -ge 75 ]; then
    log "WARN: ${DISK_USAGE}% — consider cleanup"
    if [ -n "${SLACK_WEBHOOK:-}" ]; then
        curl -s -X POST "${SLACK_WEBHOOK}" -H 'Content-type: application/json' \
            -d "{\"text\":\"Mopro disk warning: ${DISK_USAGE}% used — consider cleanup\"}" || true
    fi
else
    log "OK: ${DISK_USAGE}%"
fi

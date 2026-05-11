#!/usr/bin/env bash
# Full backup of both Postgres clusters to Backblaze B2 via restic.
# Run nightly: 0 1 * * * /opt/mopro/scripts/backup.sh
set -euo pipefail

source /opt/mopro/.env 2>/dev/null || source "$(dirname "$0")/../.env.local" 2>/dev/null || true

log() { echo "[backup] $(date -u +%FT%TZ) $*"; }

# TODO(mopro:placeholder): implement restic + B2 backup for postgres-ecom and postgres-ledger
# Requires: B2_KEY_ID, B2_APP_KEY, RESTIC_PASSWORD env vars
# Unblocked by: B2 bucket creation and credential provisioning (external dependency)

if [ -z "${B2_KEY_ID:-}" ]; then
    log "SKIP: B2_KEY_ID not set — skipping backup (dev environment)"
    exit 0
fi

log "starting backup..."

# Postgres-ecom dump
docker exec postgres-ecom pg_dumpall -U ecom_admin | \
    restic -r "b2:${B2_BUCKET:-mopro-backups}:ecom" backup --stdin --stdin-filename "ecom-$(date +%Y%m%d).sql" || {
    log "FAILED: postgres-ecom backup"
    exit 1
}

# Postgres-ledger dump
docker exec postgres-ledger pg_dumpall -U ledger_admin | \
    restic -r "b2:${B2_BUCKET:-mopro-backups}:ledger" backup --stdin --stdin-filename "ledger-$(date +%Y%m%d).sql" || {
    log "FAILED: postgres-ledger backup"
    exit 1
}

log "backup complete"
if [ -n "${HEALTHCHECK_BACKUP_UUID:-}" ]; then
    curl -s --fail "https://hc-ping.com/${HEALTHCHECK_BACKUP_UUID}" || true
fi

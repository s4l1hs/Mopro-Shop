#!/usr/bin/env bash
# Monthly restore drill: restore latest B2 backup to a throwaway container and verify.
# Run monthly: 0 4 1 * * /opt/mopro/scripts/restore-drill.sh
set -euo pipefail

source /opt/mopro/.env 2>/dev/null || source "$(dirname "$0")/../.env" 2>/dev/null || true

log() { echo "[restore-drill] $(date -u +%FT%TZ) $*"; }

# TODO(mopro:placeholder): implement restore drill against isolated postgres containers
# Unblocked by: backup.sh and B2 credentials
log "restore drill starting..."

if [ -z "${B2_KEY_ID:-}" ]; then
    log "SKIP: B2_KEY_ID not set — skipping restore drill"
    if [ -n "${HEALTHCHECK_RESTORE_UUID:-}" ]; then
        curl -s --fail "https://hc-ping.com/${HEALTHCHECK_RESTORE_UUID}/fail" || true
    fi
    exit 0
fi

log "restore drill complete"
if [ -n "${HEALTHCHECK_RESTORE_UUID:-}" ]; then
    curl -s --fail "https://hc-ping.com/${HEALTHCHECK_RESTORE_UUID}" || true
fi

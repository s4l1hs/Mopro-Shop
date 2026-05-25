#!/usr/bin/env bash
# deploy/scripts/mopro-snapshot.sh — Hourly local snapshot: pg_dump (ecom + ledger) + Redis rdb.
# Run by mopro-snapshot.timer as User=mopro, EnvironmentFile=/opt/mopro/.env.
#
# Output:  /var/lib/mopro/snapshots/{ecom,ledger}-<TS>.dump
#          /var/lib/mopro/snapshots/redis-<TS>.rdb
# Retention: last 48 files per type (≈ 2 days).
set -euo pipefail

ENV_FILE="${MOPRO_ENV_FILE:-/opt/mopro/.env}"
if [[ -f "$ENV_FILE" ]]; then
    _get_env() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d "'" | tr -d '"' || true; }
    ECOM_DB_PASSWORD="${ECOM_DB_PASSWORD:-$(_get_env ECOM_DB_PASSWORD)}"
    LEDGER_DB_PASSWORD="${LEDGER_DB_PASSWORD:-$(_get_env LEDGER_DB_PASSWORD)}"
    REDIS_PASSWORD="${REDIS_PASSWORD:-$(_get_env REDIS_PASSWORD)}"
    SLACK_PANIC_WEBHOOK="${SLACK_PANIC_WEBHOOK:-$(_get_env SLACK_PANIC_WEBHOOK)}"
fi

DUMP_DIR="${SNAPSHOT_DIR:-/var/lib/mopro/snapshots}"
TS=$(date -u +%Y%m%dT%H%M%SZ)

log()  { echo "[snapshot $(date -u +%H:%M:%S)] $*"; }
warn() { echo "[snapshot WARN $(date -u +%H:%M:%S)] $*" >&2; }

send_slack() {
    [[ -z "${SLACK_PANIC_WEBHOOK:-}" ]] && return 0
    local msg="${1//\"/\\\"}"
    curl -s -o /dev/null --max-time 10 -X POST "${SLACK_PANIC_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"${msg}\"}" || true
}

fail() {
    warn "SNAPSHOT FAILED: $*"
    send_slack ":x: *Mopro snapshot FAILED* — ${*}. Next restic backup will use stale data."
    exit 1
}

mkdir -p "${DUMP_DIR}"
log "Starting snapshot — ${TS}"

# ── Dump postgres-ecom ────────────────────────────────────────────────────────
log "pg_dump postgres-ecom..."
docker exec \
    -e PGPASSWORD="${ECOM_DB_PASSWORD}" \
    postgres-ecom \
    pg_dump -U ecom_admin -d mopro_ecom \
    --format=custom --compress=9 \
    > "${DUMP_DIR}/ecom-${TS}.dump" \
    || fail "pg_dump postgres-ecom"

ECOM_SIZE=$(du -sh "${DUMP_DIR}/ecom-${TS}.dump" 2>/dev/null | cut -f1 || echo "?")
log "ecom dump: ${ECOM_SIZE}"

# ── Dump postgres-ledger ──────────────────────────────────────────────────────
log "pg_dump postgres-ledger..."
docker exec \
    -e PGPASSWORD="${LEDGER_DB_PASSWORD}" \
    postgres-ledger \
    pg_dump -U ledger_admin -d mopro_ledger \
    --format=custom --compress=9 \
    > "${DUMP_DIR}/ledger-${TS}.dump" \
    || fail "pg_dump postgres-ledger"

LEDGER_SIZE=$(du -sh "${DUMP_DIR}/ledger-${TS}.dump" 2>/dev/null | cut -f1 || echo "?")
log "ledger dump: ${LEDGER_SIZE}"

# ── Redis BGSAVE + copy ───────────────────────────────────────────────────────
log "Redis BGSAVE..."
docker exec redis redis-cli -a "${REDIS_PASSWORD}" --no-auth-warning BGSAVE 2>/dev/null \
    || warn "redis BGSAVE command failed (non-fatal — snapshot continues)"
sleep 5
docker cp redis:/data/dump.rdb "${DUMP_DIR}/redis-${TS}.rdb" \
    || warn "redis rdb copy failed (non-fatal)"

RDB_SIZE=$(du -sh "${DUMP_DIR}/redis-${TS}.rdb" 2>/dev/null | cut -f1 || echo "?")
log "redis rdb: ${RDB_SIZE}"

# ── Retention: keep last 48 files per type ────────────────────────────────────
# 48 hourly snapshots ≈ 2 days of local recovery points.
for pattern in "ecom-*.dump" "ledger-*.dump" "redis-*.rdb"; do
    mapfile -t files < <(ls -t "${DUMP_DIR}"/${pattern} 2>/dev/null || true)
    if (( ${#files[@]} > 48 )); then
        stale=("${files[@]:48}")
        log "Removing ${#stale[@]} stale ${pattern} files..."
        rm -f -- "${stale[@]}"
    fi
done

TOTAL=$(du -sh "${DUMP_DIR}" 2>/dev/null | cut -f1 || echo "?")
log "Done. Snapshot dir: ${DUMP_DIR} (${TOTAL} total)"

#!/usr/bin/env bash
# deploy/scripts/restore-drill.sh — Weekly automated backup verification drill.
# Run by mopro-restore-drill.timer (systemd) as User=mopro, every Sunday 04:00 Istanbul.
#
# Flow:
#  1. Pull latest snapshot from B2 (fallback: Hetzner)
#  2. Spin up throwaway postgres:16 container
#  3. pg_restore both dumps
#  4. Count rows; compare against production (±1% tolerance)
#  5. Tear down container
#  6. Report to Slack + ping Healthchecks.io
#
# SAFETY: NEVER restores into the live postgres containers.
# All work is done in an ephemeral docker container that is destroyed on exit.
set -euo pipefail

# ── Load env ──────────────────────────────────────────────────────────────────
ENV_FILE="${MOPRO_ENV_FILE:-/opt/mopro/.env}"
if [[ -f "$ENV_FILE" ]]; then
    _get_env() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d "'" | tr -d '"' || true; }
    B2_KEY_ID="${B2_KEY_ID:-$(_get_env B2_KEY_ID)}"
    B2_APP_KEY="${B2_APP_KEY:-$(_get_env B2_APP_KEY)}"
    B2_BUCKET="${B2_BUCKET:-$(_get_env B2_BUCKET)}"
    HETZNER_STORAGEBOX_HOST="${HETZNER_STORAGEBOX_HOST:-$(_get_env HETZNER_STORAGEBOX_HOST)}"
    HETZNER_STORAGEBOX_USER="${HETZNER_STORAGEBOX_USER:-$(_get_env HETZNER_STORAGEBOX_USER)}"
    HETZNER_STORAGEBOX_PATH="${HETZNER_STORAGEBOX_PATH:-$(_get_env HETZNER_STORAGEBOX_PATH)}"
    RESTIC_PASSWORD="${RESTIC_PASSWORD:-$(_get_env RESTIC_PASSWORD)}"
    ECOM_DB_PASSWORD="${ECOM_DB_PASSWORD:-$(_get_env ECOM_DB_PASSWORD)}"
    LEDGER_DB_PASSWORD="${LEDGER_DB_PASSWORD:-$(_get_env LEDGER_DB_PASSWORD)}"
    HEALTHCHECK_RESTORE_UUID="${HEALTHCHECK_RESTORE_UUID:-$(_get_env HEALTHCHECK_RESTORE_UUID)}"
    SLACK_PANIC_WEBHOOK="${SLACK_PANIC_WEBHOOK:-$(_get_env SLACK_PANIC_WEBHOOK)}"
    PAGERDUTY_ROUTING_KEY="${PAGERDUTY_ROUTING_KEY:-$(_get_env PAGERDUTY_ROUTING_KEY)}"
fi

[[ -z "${RESTIC_PASSWORD:-}" ]] && { echo "FATAL: RESTIC_PASSWORD not set" >&2; exit 1; }

# ── Configuration ─────────────────────────────────────────────────────────────
B2_REPO="b2:${B2_BUCKET}:mopro-backups"
HETZNER_PATH="${HETZNER_STORAGEBOX_PATH:-/backups/mopro}"
HETZNER_REPO="sftp:mopro-hetzner-backup:${HETZNER_PATH}/mopro-backups"
DRILL_TIMESTAMP=$(date +"%Y%m%dT%H%M%S")
DRILL_CONTAINER="mopro-restore-drill-${DRILL_TIMESTAMP}"
DRILL_PGPASS="drill$(openssl rand -hex 12 2>/dev/null || date +%s)"
RESTORE_DIR=$(mktemp -d "/tmp/restore-drill-XXXXXX")
START_TIME=$(date +%s)
DRILL_OK=false
DRILL_REASON=""

export RESTIC_PASSWORD
export B2_ACCOUNT_ID="${B2_KEY_ID}"
export B2_ACCOUNT_KEY="${B2_APP_KEY}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[drill $(date -u +%H:%M:%S)] $*"; }
warn() { echo "[drill WARN] $*" >&2; }

send_slack() {
    [[ -z "${SLACK_PANIC_WEBHOOK:-}" ]] && return 0
    local msg="${1//\"/\\\"}"
    curl -s -o /dev/null --max-time 10 -X POST "${SLACK_PANIC_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"${msg}\"}" || true
}

send_pagerduty() {
    [[ -z "${PAGERDUTY_ROUTING_KEY:-}" ]] && return 0
    local summary="$1" severity="$2" dedup_key="$3"
    curl -s -o /dev/null --max-time 10 \
        -X POST "https://events.pagerduty.com/v2/enqueue" \
        -H "Content-Type: application/json" \
        -d "{\"routing_key\":\"${PAGERDUTY_ROUTING_KEY}\",\"event_action\":\"trigger\",\"dedup_key\":\"${dedup_key}\",\"payload\":{\"summary\":\"${summary}\",\"severity\":\"${severity}\",\"source\":\"mopro-restore-drill\"}}" || true
}

ping_hc() {
    local endpoint="${1:-}"
    [[ -z "${HEALTHCHECK_RESTORE_UUID:-}" ]] && return 0
    curl -fsS --max-time 10 \
        "https://hc-ping.com/${HEALTHCHECK_RESTORE_UUID}${endpoint}" \
        -o /dev/null 2>/dev/null || true
}

fail_drill() {
    DRILL_OK=false
    DRILL_REASON="$*"
    warn "DRILL FAILED: ${DRILL_REASON}"
}

# compare_counts NAME PROD_COUNT RESTORED_COUNT
# Returns 0 (pass) or 1 (fail). Allows ±1% drift.
compare_counts() {
    local name="$1" prod="$2" restored="$3"

    if (( prod == 0 && restored == 0 )); then
        echo "  ✓ ${name}: 0 == 0 (match)"
        return 0
    fi
    if (( prod == 0 && restored != 0 )); then
        echo "  ✗ ${name}: prod=0 but restored=${restored} (unexpected rows)"
        return 1
    fi

    local diff
    diff=$(( prod > restored ? prod - restored : restored - prod ))
    local pct_x100=$(( diff * 10000 / prod ))   # pct×100 for integer math (avoids floats)

    if (( pct_x100 > 100 )); then   # > 1.00%
        local pct_int=$(( pct_x100 / 100 ))
        local pct_frac=$(( pct_x100 % 100 ))
        printf "  ✗ %s: prod=%d restored=%d drift=%d.%02d%%\n" \
            "$name" "$prod" "$restored" "$pct_int" "$pct_frac"
        return 1
    fi
    echo "  ✓ ${name}: prod=${prod} restored=${restored} (within 1%)"
    return 0
}

# ── Cleanup trap (runs on any exit) ──────────────────────────────────────────
cleanup() {
    log "Tearing down drill container (if running)..."
    docker rm -f "${DRILL_CONTAINER}" 2>/dev/null || true
    rm -rf "${RESTORE_DIR}"
    log "Cleanup complete."
}
trap cleanup EXIT INT TERM

# ── Start ─────────────────────────────────────────────────────────────────────
ping_hc "/start"
log "Starting restore drill — ${DRILL_TIMESTAMP}"

# ── Pull latest snapshot from B2 (fallback to Hetzner) ───────────────────────
USED_REPO="B2"
log "Restoring latest snapshot from B2..."
RESTORE_OK=false
{
    set +x
    restic -r "${B2_REPO}" restore latest \
        --tag "env=prod" \
        --target "${RESTORE_DIR}" 2>&1 \
        && RESTORE_OK=true
    set -x
} || true

if [[ "$RESTORE_OK" != "true" ]]; then
    warn "B2 restore failed — trying Hetzner fallback..."
    USED_REPO="Hetzner"
    HETZNER_HOST="${HETZNER_STORAGEBOX_HOST:-}"
    HETZNER_USER="${HETZNER_STORAGEBOX_USER:-}"
    if [[ -n "$HETZNER_HOST" && -n "$HETZNER_USER" ]]; then
        {
            set +x
            restic -r "${HETZNER_REPO}" restore latest \
                --tag "env=prod" \
                --target "${RESTORE_DIR}" 2>&1 \
                && RESTORE_OK=true
            set -x
        } || true
    fi
    if [[ "$RESTORE_OK" != "true" ]]; then
        fail_drill "restic restore failed on both B2 and Hetzner"
        send_slack ":rotating_light: *Restore drill FAILED* — could not pull from B2 or Hetzner. Immediate action required."
        send_pagerduty "Mopro restore drill failed: cannot restore from B2 or Hetzner" "error" "mopro-restore-drill-failed"
        ping_hc "/fail"
        exit 1
    fi
fi

log "Snapshot restored from ${USED_REPO} to ${RESTORE_DIR}"

# Locate dump files in the restored snapshot (restic creates full-path hierarchy).
ECOM_DUMP=$(find "${RESTORE_DIR}" -name "ecom.dump" 2>/dev/null | head -1)
LEDGER_DUMP=$(find "${RESTORE_DIR}" -name "ledger.dump" 2>/dev/null | head -1)

if [[ -z "$ECOM_DUMP" || -z "$LEDGER_DUMP" ]]; then
    fail_drill "dump files missing from snapshot (ecom: ${ECOM_DUMP:-missing}, ledger: ${LEDGER_DUMP:-missing})"
    ping_hc "/fail"
    exit 1
fi
log "ecom.dump:   $(du -sh "${ECOM_DUMP}" | cut -f1)"
log "ledger.dump: $(du -sh "${LEDGER_DUMP}" | cut -f1)"

# ── Collect production row counts BEFORE spinning up throwaway container ──────
log "Collecting production row counts..."
prod_ecom_users=$(docker exec -e PGPASSWORD="${ECOM_DB_PASSWORD}" postgres-ecom \
    psql -U ecom_admin -d mopro_ecom -tAc "SELECT count(*) FROM identity_schema.users" 2>/dev/null || echo 0)
prod_ecom_products=$(docker exec -e PGPASSWORD="${ECOM_DB_PASSWORD}" postgres-ecom \
    psql -U ecom_admin -d mopro_ecom -tAc "SELECT count(*) FROM catalog_schema.products" 2>/dev/null || echo 0)
prod_ecom_orders=$(docker exec -e PGPASSWORD="${ECOM_DB_PASSWORD}" postgres-ecom \
    psql -U ecom_admin -d mopro_ecom -tAc "SELECT count(*) FROM order_schema.orders" 2>/dev/null || echo 0)
prod_wallet_accounts=$(docker exec -e PGPASSWORD="${LEDGER_DB_PASSWORD}" postgres-ledger \
    psql -U ledger_admin -d mopro_ledger -tAc "SELECT count(*) FROM wallet_schema.accounts" 2>/dev/null || echo 0)
prod_cashback_plans=$(docker exec -e PGPASSWORD="${LEDGER_DB_PASSWORD}" postgres-ledger \
    psql -U ledger_admin -d mopro_ledger -tAc "SELECT count(*) FROM cashback_schema.plans" 2>/dev/null || echo 0)
prod_capture_postings=$(docker exec -e PGPASSWORD="${LEDGER_DB_PASSWORD}" postgres-ledger \
    psql -U ledger_admin -d mopro_ledger -tAc "SELECT count(*) FROM commission_schema.capture_postings" 2>/dev/null || echo 0)

log "Production counts: users=${prod_ecom_users} products=${prod_ecom_products} orders=${prod_ecom_orders} wallet_accounts=${prod_wallet_accounts} cashback_plans=${prod_cashback_plans} capture_postings=${prod_capture_postings}"

# ── Spin up throwaway postgres:16 container ───────────────────────────────────
log "Starting throwaway postgres:16 container (${DRILL_CONTAINER})..."
docker run -d \
    --name "${DRILL_CONTAINER}" \
    -v "${RESTORE_DIR}:/tmp/restore:ro" \
    -e POSTGRES_PASSWORD="${DRILL_PGPASS}" \
    -e POSTGRES_USER=postgres \
    --network none \
    postgres:16-alpine

# Wait for postgres to be ready (max 30 s).
log "Waiting for postgres:16 to be ready..."
for i in $(seq 1 30); do
    if docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
        pg_isready -U postgres -q 2>/dev/null; then
        log "postgres ready after ${i}s"
        break
    fi
    if (( i == 30 )); then
        fail_drill "throwaway postgres did not become ready within 30s"
        ping_hc "/fail"
        exit 1
    fi
    sleep 1
done

# ── Create databases and restore dumps ────────────────────────────────────────
log "Creating and restoring mopro_ecom..."
docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    createdb -U postgres mopro_ecom 2>&1 || true

docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    pg_restore -U postgres -d mopro_ecom \
    --no-owner --no-acl \
    /tmp/restore/$(basename "${ECOM_DUMP}") 2>&1 | tail -5 || {
    fail_drill "pg_restore mopro_ecom failed"
    ping_hc "/fail"
    exit 1
}

log "Creating and restoring mopro_ledger..."
docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    createdb -U postgres mopro_ledger 2>&1 || true

docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    pg_restore -U postgres -d mopro_ledger \
    --no-owner --no-acl \
    /tmp/restore/$(basename "${LEDGER_DUMP}") 2>&1 | tail -5 || {
    fail_drill "pg_restore mopro_ledger failed"
    ping_hc "/fail"
    exit 1
}

# ── Collect restored row counts ───────────────────────────────────────────────
log "Collecting restored row counts..."
r_users=$(docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    psql -U postgres -d mopro_ecom -tAc "SELECT count(*) FROM identity_schema.users" 2>/dev/null || echo 0)
r_products=$(docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    psql -U postgres -d mopro_ecom -tAc "SELECT count(*) FROM catalog_schema.products" 2>/dev/null || echo 0)
r_orders=$(docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    psql -U postgres -d mopro_ecom -tAc "SELECT count(*) FROM order_schema.orders" 2>/dev/null || echo 0)
r_accounts=$(docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    psql -U postgres -d mopro_ledger -tAc "SELECT count(*) FROM wallet_schema.accounts" 2>/dev/null || echo 0)
r_plans=$(docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    psql -U postgres -d mopro_ledger -tAc "SELECT count(*) FROM cashback_schema.plans" 2>/dev/null || echo 0)
r_postings=$(docker exec -e PGPASSWORD="${DRILL_PGPASS}" "${DRILL_CONTAINER}" \
    psql -U postgres -d mopro_ledger -tAc "SELECT count(*) FROM commission_schema.capture_postings" 2>/dev/null || echo 0)

# ── Compare row counts ────────────────────────────────────────────────────────
log "Comparing row counts (±1% tolerance):"
COMPARE_OK=true
compare_counts "identity_schema.users"              "$prod_ecom_users"       "$r_users"    || COMPARE_OK=false
compare_counts "catalog_schema.products"            "$prod_ecom_products"    "$r_products" || COMPARE_OK=false
compare_counts "order_schema.orders"                "$prod_ecom_orders"      "$r_orders"   || COMPARE_OK=false
compare_counts "wallet_schema.accounts"             "$prod_wallet_accounts"  "$r_accounts" || COMPARE_OK=false
compare_counts "cashback_schema.plans"              "$prod_cashback_plans"   "$r_plans"    || COMPARE_OK=false
compare_counts "commission_schema.capture_postings" "$prod_capture_postings" "$r_postings" || COMPARE_OK=false

if [[ "$COMPARE_OK" != "true" ]]; then
    fail_drill "row count mismatch exceeds 1% tolerance"
fi

# ── Tear down (also done by cleanup trap) ─────────────────────────────────────
log "Tearing down throwaway container..."
docker rm -f "${DRILL_CONTAINER}" 2>/dev/null || true

# ── Report ────────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

if [[ "$COMPARE_OK" == "true" ]] && [[ -z "$DRILL_REASON" ]]; then
    DRILL_OK=true
fi

if [[ "$DRILL_OK" == "true" ]]; then
    log "Restore drill PASSED in ${ELAPSED}s (source: ${USED_REPO})"
    send_slack ":white_check_mark: *Restore drill PASSED* — all row counts within 1% tolerance | source: ${USED_REPO} | ${ELAPSED}s"
    ping_hc ""
else
    log "Restore drill FAILED: ${DRILL_REASON}"
    send_slack ":rotating_light: *Restore drill FAILED* — ${DRILL_REASON}. Backups may not be restorable."
    send_pagerduty "Mopro restore drill failed: ${DRILL_REASON}" "error" "mopro-restore-drill-failed"
    ping_hc "/fail"
    exit 1
fi

#!/usr/bin/env bash
# deploy/scripts/backup-postgres.sh — Nightly Postgres backup to B2 and Hetzner via restic.
# Run by mopro-backup.timer (systemd) as User=mopro, EnvironmentFile=/opt/mopro/.env.
#
# Repositories:
#   B2:      b2:${B2_BUCKET}:mopro-backups  (primary)
#   Hetzner: sftp:mopro-hetzner-backup:${HETZNER_PATH}/mopro-backups  (secondary)
#
# Retention: daily=7  weekly=4  monthly=12
# Integrity: restic check --read-data-subset=5% after each backup
set -euo pipefail

# ── Load env when run outside systemd (manual invocations) ───────────────────
ENV_FILE="${MOPRO_ENV_FILE:-/opt/mopro/.env}"
if [[ -f "$ENV_FILE" ]]; then
    # Source only the vars we need — never eval the whole file blindly.
    _get_env() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d "'" | tr -d '"' || true; }
    B2_KEY_ID="${B2_KEY_ID:-$(_get_env B2_KEY_ID)}"
    B2_APP_KEY="${B2_APP_KEY:-$(_get_env B2_APP_KEY)}"
    B2_BUCKET="${B2_BUCKET:-$(_get_env B2_BUCKET)}"
    HETZNER_STORAGEBOX_HOST="${HETZNER_STORAGEBOX_HOST:-$(_get_env HETZNER_STORAGEBOX_HOST)}"
    HETZNER_STORAGEBOX_PORT="${HETZNER_STORAGEBOX_PORT:-$(_get_env HETZNER_STORAGEBOX_PORT)}"
    HETZNER_STORAGEBOX_USER="${HETZNER_STORAGEBOX_USER:-$(_get_env HETZNER_STORAGEBOX_USER)}"
    HETZNER_STORAGEBOX_PATH="${HETZNER_STORAGEBOX_PATH:-$(_get_env HETZNER_STORAGEBOX_PATH)}"
    RESTIC_PASSWORD="${RESTIC_PASSWORD:-$(_get_env RESTIC_PASSWORD)}"
    ECOM_DB_PASSWORD="${ECOM_DB_PASSWORD:-$(_get_env ECOM_DB_PASSWORD)}"
    LEDGER_DB_PASSWORD="${LEDGER_DB_PASSWORD:-$(_get_env LEDGER_DB_PASSWORD)}"
    HEALTHCHECK_BACKUP_UUID="${HEALTHCHECK_BACKUP_UUID:-$(_get_env HEALTHCHECK_BACKUP_UUID)}"
    SLACK_PANIC_WEBHOOK="${SLACK_PANIC_WEBHOOK:-$(_get_env SLACK_PANIC_WEBHOOK)}"
    PAGERDUTY_ROUTING_KEY="${PAGERDUTY_ROUTING_KEY:-$(_get_env PAGERDUTY_ROUTING_KEY)}"
fi

# ── Guards ────────────────────────────────────────────────────────────────────
if [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    echo "[backup] FATAL: RESTIC_PASSWORD is not set. Aborting." >&2
    echo "[backup] Set RESTIC_PASSWORD in ${ENV_FILE} and re-run install-backup.sh." >&2
    exit 1
fi
if [[ -z "${B2_KEY_ID:-}" ]] || [[ -z "${B2_APP_KEY:-}" ]] || [[ -z "${B2_BUCKET:-}" ]]; then
    echo "[backup] FATAL: B2_KEY_ID / B2_APP_KEY / B2_BUCKET not configured." >&2
    exit 1
fi

# ── Configuration ─────────────────────────────────────────────────────────────
HETZNER_HOST="${HETZNER_STORAGEBOX_HOST:-}"
HETZNER_PORT="${HETZNER_STORAGEBOX_PORT:-23}"
HETZNER_USER="${HETZNER_STORAGEBOX_USER:-}"
HETZNER_PATH="${HETZNER_STORAGEBOX_PATH:-/backups/mopro}"
HETZNER_ENABLED="false"
if [[ -n "$HETZNER_HOST" && -n "$HETZNER_USER" ]]; then
    HETZNER_ENABLED="true"
fi

MAX_DURATION_SECS=300   # Alert if backup takes > 5 min
START_TIME=$(date +%s)
DATESTAMP=$(date -u +"%Y-%m-%dT%H%M%SZ")
BACKUP_HOSTNAME=$(hostname -s 2>/dev/null || echo "vds")

# B2 native backend uses f003.backblazeb2.com for downloads which is broken in eu-central-003
# (accepts TLS but never sends HTTP responses). Use S3-compatible API on different infrastructure.
B2_REPO="s3:${B2_S3_ENDPOINT:-https://s3.eu-central-003.backblazeb2.com}/${B2_BUCKET}"
HETZNER_REPO="sftp:mopro-hetzner-backup:${HETZNER_PATH}/mopro-backups"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[backup $(date -u +%H:%M:%S)] $*"; }
warn() { echo "[backup WARN $(date -u +%H:%M:%S)] $*" >&2; }

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
        -d "{\"routing_key\":\"${PAGERDUTY_ROUTING_KEY}\",\"event_action\":\"trigger\",\"dedup_key\":\"${dedup_key}\",\"payload\":{\"summary\":\"${summary}\",\"severity\":\"${severity}\",\"source\":\"mopro-backup\"}}" || true
}

ping_hc() {
    local endpoint="${1:-}"
    [[ -z "${HEALTHCHECK_BACKUP_UUID:-}" ]] && return 0
    curl -fsS --max-time 10 \
        "https://hc-ping.com/${HEALTHCHECK_BACKUP_UUID}${endpoint}" \
        -o /dev/null 2>/dev/null || true
}

fail() {
    warn "BACKUP FAILED: $*"
    send_slack ":x: *Mopro backup FAILED* — ${*}. Immediate action required."
    send_pagerduty "Mopro nightly backup failed: ${*}" "error" "mopro-backup-failed"
    ping_hc "/fail"
    exit 1
}

# ── Temp directory (cleaned up on exit) ──────────────────────────────────────
BACKUP_TMP=$(mktemp -d /tmp/mopro-backup-XXXXXX)
trap 'rm -rf "${BACKUP_TMP}"' EXIT INT TERM

# ── Signal start to Healthchecks.io ─────────────────────────────────────────
ping_hc "/start"
log "Starting backup — ${DATESTAMP}"

# ── Dump postgres-ecom ───────────────────────────────────────────────────────
log "Dumping postgres-ecom (custom format, compress=9)..."
docker exec \
    -e PGPASSWORD="${ECOM_DB_PASSWORD}" \
    postgres-ecom \
    pg_dump -U ecom_admin -d mopro_ecom \
    --format=custom --compress=9 \
    > "${BACKUP_TMP}/ecom.dump" \
    || fail "pg_dump postgres-ecom failed"

ECOM_SIZE=$(du -sh "${BACKUP_TMP}/ecom.dump" 2>/dev/null | cut -f1 || echo "?")
log "postgres-ecom dump: ${ECOM_SIZE}"

# ── Dump postgres-ledger ──────────────────────────────────────────────────────
log "Dumping postgres-ledger (custom format, compress=9)..."
docker exec \
    -e PGPASSWORD="${LEDGER_DB_PASSWORD}" \
    postgres-ledger \
    pg_dump -U ledger_admin -d mopro_ledger \
    --format=custom --compress=9 \
    > "${BACKUP_TMP}/ledger.dump" \
    || fail "pg_dump postgres-ledger failed"

LEDGER_SIZE=$(du -sh "${BACKUP_TMP}/ledger.dump" 2>/dev/null | cut -f1 || echo "?")
log "postgres-ledger dump: ${LEDGER_SIZE}"

# ── Export restic credentials (never logged — set +x wraps every restic call) ─
# shellcheck disable=SC2034
export RESTIC_PASSWORD
export B2_ACCOUNT_ID="${B2_KEY_ID}"
export B2_ACCOUNT_KEY="${B2_APP_KEY}"
# S3 backend aliases (b2: backend unusable; f003.backblazeb2.com broken in eu-central-003)
export AWS_ACCESS_KEY_ID="${B2_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${B2_APP_KEY}"
export GODEBUG="${GODEBUG:-netdns=go}"

# ── Backup to B2 (primary) ─────────────────────────────────────────────────
log "Backing up to B2 (${B2_REPO})..."
B2_OK=false
{
    set +x
    restic -r "${B2_REPO}" backup \
        --tag "db=ecom" \
        --tag "db=ledger" \
        --tag "env=prod" \
        --tag "host=${BACKUP_HOSTNAME}" \
        --hostname "${BACKUP_HOSTNAME}" \
        "${BACKUP_TMP}" 2>&1 \
        && B2_OK=true
    set -x
} || true

if [[ "$B2_OK" != "true" ]]; then
    fail "restic backup to B2 failed"
fi

B2_SNAPSHOT_ID=$(restic -r "${B2_REPO}" snapshots --tag "env=prod" --latest=1 --json 2>/dev/null \
    | grep -o '"short_id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "?")
log "B2 snapshot: ${B2_SNAPSHOT_ID}"

# ── Integrity check on B2 ─────────────────────────────────────────────────
log "Integrity check on B2 (5% sample)..."
{
    set +x
    restic -r "${B2_REPO}" check --read-data-subset=5% 2>&1 || fail "restic check B2 failed"
    set -x
}

# ── Retention / prune on B2 ───────────────────────────────────────────────
log "Applying retention policy on B2 (daily=7, weekly=4, monthly=12)..."
{
    set +x
    restic -r "${B2_REPO}" forget \
        --keep-daily=7 \
        --keep-weekly=4 \
        --keep-monthly=12 \
        --prune 2>&1 || warn "restic forget B2 failed (non-fatal)"
    set -x
}

# ── B2 storage cost guard ─────────────────────────────────────────────────
{
    set +x
    B2_STATS=$(restic -r "${B2_REPO}" stats --json 2>/dev/null || echo '{}')
    set -x
    B2_BYTES=$(echo "$B2_STATS" | grep -o '"total_size":[0-9]*' | cut -d: -f2 || echo 0)
    B2_GB=$(( ${B2_BYTES:-0} / 1073741824 ))
    log "B2 total repo size: ~${B2_GB}GB"
    if (( B2_GB > 50 )); then
        send_slack ":warning: Mopro B2 backup repo is ${B2_GB}GB — exceeds 50GB free tier. Consider resizing or archiving."
    fi
}

SNAPSHOT_COUNT=$(restic -r "${B2_REPO}" snapshots --json 2>/dev/null | grep -c '"short_id"' || echo "?")

# ── Backup to Hetzner (secondary, fail-soft) ──────────────────────────────
HETZNER_OK=false
if [[ "$HETZNER_ENABLED" == "true" ]]; then
    log "Backing up to Hetzner SFTP (${HETZNER_REPO})..."
    {
        set +x
        restic -r "${HETZNER_REPO}" backup \
            --tag "db=ecom" \
            --tag "db=ledger" \
            --tag "env=prod" \
            --tag "host=${BACKUP_HOSTNAME}" \
            --hostname "${BACKUP_HOSTNAME}" \
            "${BACKUP_TMP}" 2>&1 \
            && HETZNER_OK=true
        set -x
    } || true

    if [[ "$HETZNER_OK" != "true" ]]; then
        warn "Hetzner backup FAILED — B2 backup succeeded, alerting only"
        send_slack ":warning: Mopro Hetzner backup failed (B2 OK). Check Hetzner Storage Box."
        send_pagerduty "Mopro Hetzner backup failed (B2 succeeded)" "warning" "mopro-backup-hetzner-failed"
    else
        # Integrity check + retention on Hetzner
        {
            set +x
            restic -r "${HETZNER_REPO}" check --read-data-subset=5% 2>&1 \
                || warn "restic check Hetzner failed (non-fatal — B2 is primary)"
            restic -r "${HETZNER_REPO}" forget \
                --keep-daily=7 \
                --keep-weekly=4 \
                --keep-monthly=12 \
                --prune 2>&1 \
                || warn "restic forget Hetzner failed (non-fatal)"
            set -x
        }
        log "Hetzner backup OK"
    fi
else
    warn "Hetzner Storage Box not configured (HETZNER_STORAGEBOX_HOST missing) — skipping"
    send_slack ":information_source: Mopro backup: Hetzner destination not configured. B2 only."
fi

# ── Duration guard ────────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
log "Backup completed in ${ELAPSED}s"
if (( ELAPSED > MAX_DURATION_SECS )); then
    send_slack ":warning: Mopro backup took ${ELAPSED}s (>${MAX_DURATION_SECS}s) — possible B2 throughput issue"
fi

# ── Success notification ──────────────────────────────────────────────────
HETZNER_STATUS="${HETZNER_OK}"
[[ "$HETZNER_ENABLED" == "false" ]] && HETZNER_STATUS="skipped"
send_slack ":white_check_mark: *Mopro backup OK* — ecom: ${ECOM_SIZE}, ledger: ${LEDGER_SIZE}, snapshot: ${B2_SNAPSHOT_ID}, total: ${SNAPSHOT_COUNT}, ${ELAPSED}s | Hetzner: ${HETZNER_STATUS}"
ping_hc ""
log "Done."

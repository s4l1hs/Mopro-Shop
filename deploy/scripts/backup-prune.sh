#!/usr/bin/env bash
# deploy/scripts/backup-prune.sh — Weekly restic retention prune for B2 (+ Hetzner if configured).
# Run by mopro-backup-prune.timer (Sundays 04:30 Istanbul) as User=mopro.
# Retention policy: daily=7, weekly=4, monthly=6.
#
# NOTE: The daily backup-postgres.sh also prunes inline.  This separate weekly
# prune is a belt-and-suspenders run that catches any orphaned packs after the
# inline prune and compacts the repo.
set -euo pipefail

ENV_FILE="${MOPRO_ENV_FILE:-/opt/mopro/.env}"
if [[ -f "$ENV_FILE" ]]; then
    _get_env() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d "'" | tr -d '"' || true; }
    B2_KEY_ID="${B2_KEY_ID:-$(_get_env B2_KEY_ID)}"
    B2_APP_KEY="${B2_APP_KEY:-$(_get_env B2_APP_KEY)}"
    B2_BUCKET="${B2_BUCKET:-$(_get_env B2_BUCKET)}"
    RESTIC_PASSWORD="${RESTIC_PASSWORD:-$(_get_env RESTIC_PASSWORD)}"
    HETZNER_STORAGEBOX_HOST="${HETZNER_STORAGEBOX_HOST:-$(_get_env HETZNER_STORAGEBOX_HOST)}"
    HETZNER_STORAGEBOX_USER="${HETZNER_STORAGEBOX_USER:-$(_get_env HETZNER_STORAGEBOX_USER)}"
    HETZNER_STORAGEBOX_PATH="${HETZNER_STORAGEBOX_PATH:-$(_get_env HETZNER_STORAGEBOX_PATH)}"
    SLACK_PANIC_WEBHOOK="${SLACK_PANIC_WEBHOOK:-$(_get_env SLACK_PANIC_WEBHOOK)}"
fi

[[ -z "${RESTIC_PASSWORD:-}" ]] && { echo "[prune] FATAL: RESTIC_PASSWORD not set" >&2; exit 1; }
[[ -z "${B2_KEY_ID:-}" ]]       && { echo "[prune] FATAL: B2_KEY_ID not set" >&2; exit 1; }

export RESTIC_PASSWORD
export B2_ACCOUNT_ID="${B2_KEY_ID}"
export B2_ACCOUNT_KEY="${B2_APP_KEY}"
# S3 backend aliases (b2: backend unusable; f003.backblazeb2.com broken in eu-central-003)
export AWS_ACCESS_KEY_ID="${B2_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${B2_APP_KEY}"
export GODEBUG="${GODEBUG:-netdns=go}"

# B2 native backend download URL (f003.backblazeb2.com) is broken; use S3-compatible API.
B2_REPO="s3:${B2_S3_ENDPOINT:-https://s3.eu-central-003.backblazeb2.com}/${B2_BUCKET}"

log()  { echo "[prune $(date -u +%H:%M:%S)] $*"; }
warn() { echo "[prune WARN $(date -u +%H:%M:%S)] $*" >&2; }

send_slack() {
    [[ -z "${SLACK_PANIC_WEBHOOK:-}" ]] && return 0
    local msg="${1//\"/\\\"}"
    curl -s -o /dev/null --max-time 10 -X POST "${SLACK_PANIC_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"${msg}\"}" || true
}

log "Starting weekly prune on B2 (${B2_REPO})..."
{
    set +x
    restic -r "${B2_REPO}" forget \
        --keep-daily=7 \
        --keep-weekly=4 \
        --keep-monthly=6 \
        --prune 2>&1
    set -x
} || { warn "prune failed"; send_slack ":warning: Mopro weekly restic prune FAILED on B2."; exit 1; }

log "B2 prune OK."

# Hetzner (optional, fail-soft)
HETZNER_HOST="${HETZNER_STORAGEBOX_HOST:-}"
HETZNER_USER="${HETZNER_STORAGEBOX_USER:-}"
HETZNER_PATH="${HETZNER_STORAGEBOX_PATH:-/backups/mopro}"
if [[ -n "$HETZNER_HOST" && -n "$HETZNER_USER" ]]; then
    HETZNER_REPO="sftp:mopro-hetzner-backup:${HETZNER_PATH}/mopro-backups"
    log "Pruning Hetzner (${HETZNER_REPO})..."
    {
        set +x
        restic -r "${HETZNER_REPO}" forget \
            --keep-daily=7 \
            --keep-weekly=4 \
            --keep-monthly=6 \
            --prune 2>&1 || warn "Hetzner prune failed (non-fatal)"
        set -x
    }
fi

STATS=$(restic -r "${B2_REPO}" stats --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('total_size',0)//1048576}MB / {d.get('snapshots_count',0)} snapshots\")" 2>/dev/null || echo "stats unavailable")
send_slack ":broom: *Mopro weekly prune OK* — B2 repo: ${STATS}"
log "Done."

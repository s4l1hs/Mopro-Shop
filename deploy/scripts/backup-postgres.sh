#!/usr/bin/env bash
# deploy/scripts/backup-postgres.sh — Daily Postgres backup to Hetzner Storage Box.
# Run by mopro-backup.timer (systemd) as User=mopro.
# Requires: /etc/mopro/.env populated with HETZNER_STORAGEBOX_* vars.
set -euo pipefail

ENV_FILE="/etc/mopro/.env"
MOPRO_DIR="/opt/mopro"
LOCAL_BACKUP_DIR="${MOPRO_DIR}/backups"
RETENTION_DAYS=7

# Load env (only the vars we need; never eval the whole file)
_get_env() { grep -E "^${1}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || true; }

HETZNER_HOST="${HETZNER_STORAGEBOX_HOST:-$(_get_env HETZNER_STORAGEBOX_HOST)}"
HETZNER_USER="${HETZNER_STORAGEBOX_USER:-$(_get_env HETZNER_STORAGEBOX_USER)}"
HETZNER_PORT="${HETZNER_STORAGEBOX_PORT:-$(_get_env HETZNER_STORAGEBOX_PORT)}"
HETZNER_PORT="${HETZNER_PORT:-23}"
HETZNER_PATH="${HETZNER_STORAGEBOX_PATH:-$(_get_env HETZNER_STORAGEBOX_PATH)}"
HETZNER_PATH="${HETZNER_PATH:-/backups/mopro}"
HEALTHCHECK_UUID="${HEALTHCHECK_BACKUP_UUID:-$(_get_env HEALTHCHECK_BACKUP_UUID)}"

ECOM_PASS="$(_get_env ECOM_DB_PASSWORD)"
LEDGER_PASS="$(_get_env LEDGER_DB_PASSWORD)"

DATESTAMP="$(date -u '+%Y-%m-%dT%H%M%SZ')"
BACKUP_SSH_KEY="/home/mopro/.ssh/mopro_hetzner_backup"

# ── Guard: skip if Hetzner vars not set ──────────────────────────────────────
if [[ -z "${HETZNER_HOST}" ]]; then
  echo "[backup] HETZNER_STORAGEBOX_HOST not set — skipping offsite upload"
fi

mkdir -p "${LOCAL_BACKUP_DIR}"

_ping_healthcheck() {
  local uuid="$1" endpoint="$2"
  [[ -z "${uuid}" ]] && return 0
  curl -fsS --max-time 10 \
    "https://hc-ping.com/${uuid}${endpoint}" -o /dev/null 2>/dev/null || true
}

# ── Signal start ─────────────────────────────────────────────────────────────
_ping_healthcheck "${HEALTHCHECK_UUID}" "/start"

echo "[backup] Starting — ${DATESTAMP}"

# ── Dump postgres-ecom ───────────────────────────────────────────────────────
ECOM_FILE="${LOCAL_BACKUP_DIR}/postgres-ecom-${DATESTAMP}.sql.gz"
echo "[backup] Dumping postgres-ecom..."
PGPASSWORD="${ECOM_PASS}" docker exec postgres-ecom \
  pg_dumpall -U ecom_admin --clean --if-exists \
  | gzip > "${ECOM_FILE}"
echo "[backup] postgres-ecom: $(du -sh "${ECOM_FILE}" | cut -f1)"

# ── Dump postgres-ledger ─────────────────────────────────────────────────────
LEDGER_FILE="${LOCAL_BACKUP_DIR}/postgres-ledger-${DATESTAMP}.sql.gz"
echo "[backup] Dumping postgres-ledger..."
PGPASSWORD="${LEDGER_PASS}" docker exec postgres-ledger \
  pg_dumpall -U ledger_admin --clean --if-exists \
  | gzip > "${LEDGER_FILE}"
echo "[backup] postgres-ledger: $(du -sh "${LEDGER_FILE}" | cut -f1)"

# ── Offsite rsync to Hetzner Storage Box ─────────────────────────────────────
if [[ -n "${HETZNER_HOST}" ]] && [[ -n "${HETZNER_USER}" ]]; then
  echo "[backup] Uploading to Hetzner Storage Box..."
  rsync -az --delete \
    -e "ssh -p ${HETZNER_PORT} -i ${BACKUP_SSH_KEY} \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=30" \
    "${LOCAL_BACKUP_DIR}/" \
    "${HETZNER_USER}@${HETZNER_HOST}:${HETZNER_PATH}/"
  echo "[backup] Offsite upload complete"
else
  echo "[backup] Hetzner not configured — local backup only"
fi

# ── Local retention: remove files older than RETENTION_DAYS ──────────────────
echo "[backup] Pruning local backups older than ${RETENTION_DAYS} days..."
find "${LOCAL_BACKUP_DIR}" -maxdepth 1 \
  -name "postgres-*.sql.gz" \
  -mtime "+${RETENTION_DAYS}" \
  -delete

echo "[backup] Done — ${DATESTAMP}"
_ping_healthcheck "${HEALTHCHECK_UUID}" ""

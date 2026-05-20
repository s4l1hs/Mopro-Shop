#!/usr/bin/env bash
# deploy/scripts/restore-postgres.sh — Restore Postgres from a dated backup.
# Usage: restore-postgres.sh --db ecom|ledger --date 2026-05-20T040000Z --confirm YES
# WARNING: This DROPS and recreates all databases. Requires explicit --confirm YES.
set -euo pipefail

DB=""
DATE=""
CONFIRM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)      DB="$2";      shift 2 ;;
    --date)    DATE="$2";    shift 2 ;;
    --confirm) CONFIRM="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${DB}" ]] || [[ -z "${DATE}" ]]; then
  echo "Usage: restore-postgres.sh --db ecom|ledger --date <DATESTAMP> --confirm YES" >&2
  exit 1
fi

if [[ "${CONFIRM}" != "YES" ]]; then
  echo "ERROR: Pass --confirm YES to confirm destructive restore." >&2
  exit 1
fi

MOPRO_DIR="/opt/mopro"
LOCAL_BACKUP_DIR="${MOPRO_DIR}/backups"
ENV_FILE="/etc/mopro/.env"

_get_env() { grep -E "^${1}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || true; }

case "${DB}" in
  ecom)
    CONTAINER="postgres-ecom"
    PGUSER="ecom_admin"
    PGPASS="$(_get_env ECOM_DB_PASSWORD)"
    BACKUP_FILE="${LOCAL_BACKUP_DIR}/postgres-ecom-${DATE}.sql.gz"
    ;;
  ledger)
    CONTAINER="postgres-ledger"
    PGUSER="ledger_admin"
    PGPASS="$(_get_env LEDGER_DB_PASSWORD)"
    BACKUP_FILE="${LOCAL_BACKUP_DIR}/postgres-ledger-${DATE}.sql.gz"
    ;;
  *)
    echo "ERROR: --db must be ecom or ledger" >&2
    exit 1
    ;;
esac

if [[ ! -f "${BACKUP_FILE}" ]]; then
  echo "ERROR: Backup file not found: ${BACKUP_FILE}" >&2
  echo "Available backups:" >&2
  ls -lh "${LOCAL_BACKUP_DIR}"/postgres-"${DB}"-*.sql.gz 2>/dev/null || echo "  (none)" >&2
  exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo " RESTORE — ${DB} from ${BACKUP_FILE}"
echo " Container: ${CONTAINER}"
echo " This will OVERWRITE all data. Press Ctrl-C to abort."
echo "═══════════════════════════════════════════════════════"
sleep 5

echo "[restore] Stopping services that use ${DB}..."
if [[ "${DB}" == "ecom" ]]; then
  docker stop core-svc jobs-svc pgbouncer-ecom 2>/dev/null || true
else
  docker stop fin-svc pgbouncer-ledger 2>/dev/null || true
fi

echo "[restore] Applying backup ${BACKUP_FILE}..."
PGPASSWORD="${PGPASS}" zcat "${BACKUP_FILE}" \
  | docker exec -i "${CONTAINER}" psql -U "${PGUSER}" postgres

echo "[restore] Restarting services..."
docker start pgbouncer-ecom pgbouncer-ledger core-svc fin-svc jobs-svc 2>/dev/null || true

echo ""
echo "[restore] Complete. Verify data integrity before resuming traffic."

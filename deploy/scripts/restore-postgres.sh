#!/usr/bin/env bash
# deploy/scripts/restore-postgres.sh — Restore Postgres from a restic snapshot.
#
# Usage:
#   restore-postgres.sh --db ecom|ledger --snapshot latest|<snapshot-id> --confirm YES
#   restore-postgres.sh --db ecom --snapshot 1a2b3c4d --confirm YES
#
# WARNING: This STOPS services, drops, and recreates all databases in the target cluster.
# Pass --confirm YES explicitly. There is a 10-second countdown you can abort.
#
# The restore always pulls from B2 (primary). Pass --repo hetzner to use Hetzner.
set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
DB=""
SNAPSHOT_ID="latest"
CONFIRM=""
REPO_TARGET="b2"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)       DB="$2";           shift 2 ;;
        --snapshot) SNAPSHOT_ID="$2";  shift 2 ;;
        --confirm)  CONFIRM="$2";      shift 2 ;;
        --repo)     REPO_TARGET="$2";  shift 2 ;;
        --help|-h)
            grep '^#' "$0" | head -10 | sed 's/^# //'
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$DB" ]]; then
    echo "Usage: $0 --db ecom|ledger [--snapshot latest|<id>] [--repo b2|hetzner] --confirm YES" >&2
    exit 1
fi
if [[ "$CONFIRM" != "YES" ]]; then
    echo "ERROR: Pass --confirm YES to confirm destructive restore." >&2
    exit 1
fi
if [[ "$DB" != "ecom" && "$DB" != "ledger" ]]; then
    echo "ERROR: --db must be 'ecom' or 'ledger'" >&2
    exit 1
fi

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
fi

[[ -z "${RESTIC_PASSWORD:-}" ]] && { echo "FATAL: RESTIC_PASSWORD not set" >&2; exit 1; }
export RESTIC_PASSWORD
export B2_ACCOUNT_ID="${B2_KEY_ID}"
export B2_ACCOUNT_KEY="${B2_APP_KEY}"

# ── Select repo and DB config ─────────────────────────────────────────────────
B2_REPO="b2:${B2_BUCKET}:mopro-backups"
HETZNER_PATH="${HETZNER_STORAGEBOX_PATH:-/backups/mopro}"
HETZNER_REPO="sftp:mopro-hetzner-backup:${HETZNER_PATH}/mopro-backups"

case "$REPO_TARGET" in
    b2)      RESTIC_REPO="${B2_REPO}" ;;
    hetzner) RESTIC_REPO="${HETZNER_REPO}" ;;
    *)       echo "ERROR: --repo must be b2 or hetzner" >&2; exit 1 ;;
esac

case "$DB" in
    ecom)
        CONTAINER="postgres-ecom"
        PGUSER="ecom_admin"
        PGPASS="${ECOM_DB_PASSWORD}"
        DUMP_FILE="ecom.dump"
        SERVICES_TO_STOP="core-svc jobs-svc pgbouncer-ecom"
        DBNAME="mopro_ecom"
        ;;
    ledger)
        CONTAINER="postgres-ledger"
        PGUSER="ledger_admin"
        PGPASS="${LEDGER_DB_PASSWORD}"
        DUMP_FILE="ledger.dump"
        SERVICES_TO_STOP="fin-svc pgbouncer-ledger"
        DBNAME="mopro_ledger"
        ;;
esac

# ── Temp dir for restore ──────────────────────────────────────────────────────
RESTORE_TMP=$(mktemp -d /tmp/mopro-restore-XXXXXX)
trap 'rm -rf "${RESTORE_TMP}"' EXIT INT TERM

# ── List available snapshots ──────────────────────────────────────────────────
echo ""
echo "Available snapshots in ${REPO_TARGET}:"
{
    set +x
    restic -r "${RESTIC_REPO}" snapshots --tag "env=prod" 2>&1
    set -x
} || true
echo ""

# ── Countdown ────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo " RESTORE — DB: ${DB}  Snapshot: ${SNAPSHOT_ID}  Repo: ${REPO_TARGET}"
echo " Container: ${CONTAINER} / DB: ${DBNAME}"
echo " Services to stop: ${SERVICES_TO_STOP}"
echo " This OVERWRITES all data. Press Ctrl-C to abort."
echo "═══════════════════════════════════════════════════════════"
for i in 10 9 8 7 6 5 4 3 2 1; do
    printf "\rStarting in %2d seconds... " "$i"
    sleep 1
done
echo ""

# ── Restore snapshot to temp dir ─────────────────────────────────────────────
echo "[restore] Restoring snapshot '${SNAPSHOT_ID}' from ${REPO_TARGET}..."
{
    set +x
    restic -r "${RESTIC_REPO}" restore "${SNAPSHOT_ID}" \
        --target "${RESTORE_TMP}" \
        --tag "env=prod" 2>&1
    set -x
}

DUMP_PATH=$(find "${RESTORE_TMP}" -name "${DUMP_FILE}" 2>/dev/null | head -1)
if [[ -z "$DUMP_PATH" ]]; then
    echo "ERROR: ${DUMP_FILE} not found in restored snapshot" >&2
    echo "Contents of restore dir:" >&2
    find "${RESTORE_TMP}" -type f >&2
    exit 1
fi
echo "[restore] Dump found: ${DUMP_PATH} ($(du -sh "${DUMP_PATH}" | cut -f1))"

# ── Stop dependent services ───────────────────────────────────────────────────
echo "[restore] Stopping services: ${SERVICES_TO_STOP}"
for svc in $SERVICES_TO_STOP; do
    docker stop "$svc" 2>/dev/null && echo "  stopped $svc" || echo "  $svc not running"
done

# ── Apply restore via pg_restore ─────────────────────────────────────────────
echo "[restore] Dropping and recreating database ${DBNAME}..."
docker exec -e PGPASSWORD="${PGPASS}" "${CONTAINER}" \
    psql -U "${PGUSER}" -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DBNAME}' AND pid <> pg_backend_pid();" \
    > /dev/null 2>&1 || true

docker exec -e PGPASSWORD="${PGPASS}" "${CONTAINER}" \
    dropdb -U "${PGUSER}" --if-exists "${DBNAME}" || true

docker exec -e PGPASSWORD="${PGPASS}" "${CONTAINER}" \
    createdb -U "${PGUSER}" "${DBNAME}"

echo "[restore] Restoring ${DUMP_PATH} into ${DBNAME}..."
docker cp "${DUMP_PATH}" "${CONTAINER}:/tmp/restore_input.dump"
docker exec -e PGPASSWORD="${PGPASS}" "${CONTAINER}" \
    pg_restore -U "${PGUSER}" -d "${DBNAME}" \
    --no-owner --no-acl \
    --verbose \
    /tmp/restore_input.dump 2>&1 | tail -20
docker exec "${CONTAINER}" rm -f /tmp/restore_input.dump

# ── Restart services ──────────────────────────────────────────────────────────
echo "[restore] Restarting services..."
for svc in $SERVICES_TO_STOP; do
    docker start "$svc" 2>/dev/null && echo "  started $svc" || echo "  failed to start $svc"
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Restore COMPLETE."
echo " Run integrity checks:"
echo "   docker exec postgres-${DB} psql -U ${PGUSER} -d ${DBNAME} -c 'SELECT now()'"
echo " Monitor logs:"
echo "   docker logs --tail=100 -f ${CONTAINER}"
echo "═══════════════════════════════════════════════════════════"

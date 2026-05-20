#!/usr/bin/env bash
# deploy/scripts/apply-migration.sh — Apply a SQL migration file to postgres-ecom or postgres-ledger.
# Usage: ./deploy/scripts/apply-migration.sh --db ecom|ledger|config --file <path>
# Tracks applied migrations in a _migrations table to prevent double-apply.
set -euo pipefail

DB=""
MIGRATION_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)   DB="$2";             shift 2 ;;
    --file) MIGRATION_FILE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${DB}" ]] || [[ -z "${MIGRATION_FILE}" ]]; then
  echo "Usage: apply-migration.sh --db ecom|ledger|config --file <path>" >&2
  exit 1
fi

if [[ ! -f "${MIGRATION_FILE}" ]]; then
  echo "ERROR: Migration file not found: ${MIGRATION_FILE}" >&2
  exit 1
fi

case "${DB}" in
  ecom)
    PGHOST="postgres-ecom"
    PGUSER="ecom_admin"
    PGDB="mopro_ecom"
    PGPASS_VAR="ECOM_DB_PASSWORD"
    ;;
  ledger)
    PGHOST="postgres-ledger"
    PGUSER="ledger_admin"
    PGDB="mopro_ledger"
    PGPASS_VAR="LEDGER_DB_PASSWORD"
    ;;
  config)
    PGHOST="postgres-config"
    PGUSER="config_admin"
    PGDB="mopro_config"
    PGPASS_VAR="ECOM_DB_PASSWORD"
    ;;
  *)
    echo "ERROR: --db must be one of: ecom, ledger, config" >&2
    exit 1
    ;;
esac

MIGRATION_NAME="$(basename "${MIGRATION_FILE}")"
SERVER="${SERVER:-mopro@195.85.207.92}"
SSH_PORT="${SSH_PORT:-4625}"

_ssh() { ssh -p "${SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER}" "$@"; }
_scp() { scp -P "${SSH_PORT}" "$@"; }

echo "Applying migration '${MIGRATION_NAME}' to ${DB} (${PGDB})..."

# Upload migration file to VDS
_scp "${MIGRATION_FILE}" "${SERVER}:/tmp/mopro_migration_$$.sql"

# Apply via direct psql into the Postgres container (bypasses PgBouncer for DDL)
_ssh "
  set -euo pipefail
  PGPASSWORD=\"\$(grep '^${PGPASS_VAR}=' /etc/mopro/.env | cut -d= -f2-)\"
  export PGPASSWORD

  # Create _migrations tracking table if absent
  docker exec -i '${PGHOST}' psql -U '${PGUSER}' -d '${PGDB}' <<'SQL'
CREATE TABLE IF NOT EXISTS _migrations (
  name       TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

  # Check if already applied
  already=\$(docker exec -i '${PGHOST}' psql -U '${PGUSER}' -d '${PGDB}' -tAq \
    -c \"SELECT 1 FROM _migrations WHERE name = '${MIGRATION_NAME}'\")
  if [[ \"\${already}\" == '1' ]]; then
    echo '  SKIP: ${MIGRATION_NAME} already applied.'
    rm -f /tmp/mopro_migration_$$.sql
    exit 0
  fi

  # Apply
  echo '  Applying ${MIGRATION_NAME}...'
  docker exec -i '${PGHOST}' psql -U '${PGUSER}' -d '${PGDB}' \
    < /tmp/mopro_migration_$$.sql

  # Record
  docker exec -i '${PGHOST}' psql -U '${PGUSER}' -d '${PGDB}' \
    -c \"INSERT INTO _migrations(name) VALUES ('${MIGRATION_NAME}')\"

  rm -f /tmp/mopro_migration_$$.sql
  echo '  OK: ${MIGRATION_NAME} applied and recorded.'
"

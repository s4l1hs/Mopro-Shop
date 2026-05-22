#!/usr/bin/env bash
# deploy/scripts/apply-migration.sh — Run golang-migrate managed migrations on VDS.
#
# Usage: ./deploy/scripts/apply-migration.sh --db <ecom|ledger> <up|down|status>
#
# Builds a linux/amd64 static migrate-tool binary locally, copies it + the
# migrations/ directory to VDS, then runs the tool as a one-shot Docker container
# on the appropriate Docker network so it can reach postgres directly (bypassing
# PgBouncer — DDL requires a direct connection).
#
# Requirements on VDS: Docker, /opt/mopro/.env with DB passwords present.
set -euo pipefail

DB=""
CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    up|down|status) CMD="$1"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${DB}" ]] || [[ -z "${CMD}" ]]; then
  echo "Usage: apply-migration.sh --db <ecom|ledger> <up|down|status>" >&2
  exit 1
fi

case "${DB}" in
  ecom|ledger) ;;
  *) echo "ERROR: --db must be ecom or ledger" >&2; exit 1 ;;
esac

SERVER="${SERVER:-mopro@195.85.207.92}"
SSH_PORT="${SSH_PORT:-4625}"
MOPRO_DIR="${MOPRO_DIR:-/opt/mopro}"

_ssh() { ssh -p "${SSH_PORT}" -o StrictHostKeyChecking=accept-new "${SERVER}" "$@"; }
_scp() { scp -P "${SSH_PORT}" -o StrictHostKeyChecking=accept-new "$@"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN_OUT="/tmp/mopro-migrate-tool-linux"

echo "[1/4] Building migrate-tool (linux/amd64 static binary)..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -trimpath -ldflags="-s -w" \
  -o "${BIN_OUT}" \
  "${REPO_ROOT}/cmd/migrate-tool"
echo "      → ${BIN_OUT}"

echo "[2/4] Copying binary and migrations to VDS..."
_scp "${BIN_OUT}" "${SERVER}:${MOPRO_DIR}/bin/migrate-tool"
_ssh "chmod 755 ${MOPRO_DIR}/bin/migrate-tool"

# Sync migrations directory (rsync-like via tar pipe to avoid rsync dependency)
tar -C "${REPO_ROOT}" -czf - migrations | \
  _ssh "tar -C ${MOPRO_DIR} -xzf -"
echo "      → ${MOPRO_DIR}/migrations/ synced"

echo "[3/4] Constructing DSN on VDS..."
_ssh "
  set -euo pipefail
  source /etc/mopro/.env 2>/dev/null || true

  case '${DB}' in
    ecom)
      PASS=\${ECOM_DB_PASSWORD:?ECOM_DB_PASSWORD not set in /etc/mopro/.env}
      DSN=\"postgres://ecom_admin:\${PASS}@postgres-ecom:5432/mopro_ecom\"
      NETWORK=\"mopro-net\"
      ;;
    ledger)
      PASS=\${LEDGER_DB_PASSWORD:?LEDGER_DB_PASSWORD not set in /etc/mopro/.env}
      DSN=\"postgres://ledger_admin:\${PASS}@postgres-ledger:5432/mopro_ledger\"
      NETWORK=\"mopro-fin-net\"
      ;;
  esac

  echo '[4/4] Running migrate-tool --db ${DB} ${CMD}...'
  docker run --rm \
    --network \"\${NETWORK}\" \
    -v ${MOPRO_DIR}/bin/migrate-tool:/migrate-tool:ro \
    -v ${MOPRO_DIR}/migrations:/migrations:ro \
    -e ECOM_DATABASE_URL=\"\${DSN}\" \
    -e LEDGER_DATABASE_URL=\"\${DSN}\" \
    -e MIGRATIONS_DIR=/migrations \
    alpine:3.19 \
    /migrate-tool --db ${DB} ${CMD}
"

echo ""
echo "apply-migration.sh complete: db=${DB} cmd=${CMD}"

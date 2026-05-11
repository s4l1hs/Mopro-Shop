#!/usr/bin/env bash
# 99-set-passwords.sh — replace placeholder passwords with real secrets from env.
# Called once by Docker Compose entrypoint after SQL init scripts complete.
# Env vars must be set in /opt/mopro/.env or Docker Compose secrets.
set -euo pipefail

: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGDATABASE:=mopro_ledger}"

psql() {
  command psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" "$@"
}

alter_password() {
  local role="$1"
  local env_var="$2"
  local pw="${!env_var:-}"
  if [ -z "${pw}" ]; then
    echo "[99-set-passwords] SKIP ${role}: ${env_var} not set"
    return
  fi
  psql -c "ALTER ROLE ${role} PASSWORD '${pw}';"
  echo "[99-set-passwords] password set for ${role}"
}

alter_password wallet_user       WALLET_DB_PASSWORD
alter_password commission_user   COMMISSION_DB_PASSWORD
alter_password treasury_user     TREASURY_DB_PASSWORD
alter_password cashback_user     CASHBACK_DB_PASSWORD
alter_password sellerpayout_user SELLERPAYOUT_DB_PASSWORD

echo "[99-set-passwords] done"

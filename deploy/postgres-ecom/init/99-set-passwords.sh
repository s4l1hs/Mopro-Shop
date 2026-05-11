#!/usr/bin/env bash
# 99-set-passwords.sh — replace placeholder passwords with real secrets from env.
# Called once by Docker Compose entrypoint after SQL init scripts complete.
# Env vars must be set in /opt/mopro/.env or Docker Compose secrets.
set -euo pipefail

: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGDATABASE:=mopro_ecom}"

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

alter_password identity_user     IDENTITY_DB_PASSWORD
alter_password catalog_user      CATALOG_DB_PASSWORD
alter_password cart_user         CART_DB_PASSWORD
alter_password order_user        ORDER_DB_PASSWORD
alter_password payment_user      PAYMENT_DB_PASSWORD
alter_password seller_user       SELLER_DB_PASSWORD
alter_password search_user       SEARCH_DB_PASSWORD
alter_password notification_user NOTIFICATION_DB_PASSWORD
alter_password support_user      SUPPORT_DB_PASSWORD
alter_password media_user        MEDIA_DB_PASSWORD
alter_password sizefinder_user   SIZEFINDER_DB_PASSWORD
alter_password antifraud_user    ANTIFRAUD_DB_PASSWORD
alter_password einvoice_user     EINVOICE_DB_PASSWORD

echo "[99-set-passwords] done"

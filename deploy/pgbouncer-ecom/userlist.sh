#!/usr/bin/env sh
# deploy/pgbouncer-ecom/userlist.sh
# Generates /etc/pgbouncer/userlist.txt from environment variables at startup.
# Mounted into pgbouncer-ecom container; run before pgbouncer starts.
# PgBouncer scram-sha-256: userlist format is:
#   "username" "SCRAM-SHA-256$<iter>:<salt>$<storedkey>:<serverkey>"
# For simplicity in Phase 4.0.5 we store plaintext passwords here
# (PgBouncer supports plaintext in userlist even with auth_type=scram-sha-256
# when server uses md5/scram — the connection to upstream Postgres uses the
# password from userlist directly). Phase N TODO: use pg_shadow hashes.
set -eu

OUT="/etc/pgbouncer/userlist.txt"

: "${ECOM_DB_PASSWORD:?ECOM_DB_PASSWORD must be set}"
: "${IDENTITY_DB_PASSWORD:?IDENTITY_DB_PASSWORD must be set}"
: "${CATALOG_DB_PASSWORD:?CATALOG_DB_PASSWORD must be set}"
: "${CART_DB_PASSWORD:?CART_DB_PASSWORD must be set}"
: "${ORDER_DB_PASSWORD:?ORDER_DB_PASSWORD must be set}"
: "${PAYMENT_DB_PASSWORD:?PAYMENT_DB_PASSWORD must be set}"
: "${SELLER_DB_PASSWORD:?SELLER_DB_PASSWORD must be set}"
: "${SEARCH_DB_PASSWORD:?SEARCH_DB_PASSWORD must be set}"
: "${NOTIFICATION_DB_PASSWORD:?NOTIFICATION_DB_PASSWORD must be set}"
: "${SUPPORT_DB_PASSWORD:?SUPPORT_DB_PASSWORD must be set}"
: "${MEDIA_DB_PASSWORD:?MEDIA_DB_PASSWORD must be set}"
: "${SIZEFINDER_DB_PASSWORD:?SIZEFINDER_DB_PASSWORD must be set}"
: "${ANTIFRAUD_DB_PASSWORD:?ANTIFRAUD_DB_PASSWORD must be set}"
: "${EINVOICE_DB_PASSWORD:?EINVOICE_DB_PASSWORD must be set}"

cat > "${OUT}" <<EOF
"ecom_admin"       "${ECOM_DB_PASSWORD}"
"identity_user"    "${IDENTITY_DB_PASSWORD}"
"catalog_user"     "${CATALOG_DB_PASSWORD}"
"cart_user"        "${CART_DB_PASSWORD}"
"order_user"       "${ORDER_DB_PASSWORD}"
"payment_user"     "${PAYMENT_DB_PASSWORD}"
"seller_user"      "${SELLER_DB_PASSWORD}"
"search_user"      "${SEARCH_DB_PASSWORD}"
"notification_user" "${NOTIFICATION_DB_PASSWORD}"
"support_user"     "${SUPPORT_DB_PASSWORD}"
"media_user"       "${MEDIA_DB_PASSWORD}"
"sizefinder_user"  "${SIZEFINDER_DB_PASSWORD}"
"antifraud_user"   "${ANTIFRAUD_DB_PASSWORD}"
"einvoice_user"    "${EINVOICE_DB_PASSWORD}"
EOF

chmod 600 "${OUT}"
echo "pgbouncer-ecom: userlist.txt written (${OUT})"

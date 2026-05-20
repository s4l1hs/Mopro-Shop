#!/usr/bin/env sh
# deploy/pgbouncer-ledger/userlist.sh
# Generates /etc/pgbouncer/userlist.txt for the ledger-side PgBouncer.
# Mounted into pgbouncer-ledger container; run before pgbouncer starts.
set -eu

OUT="/etc/pgbouncer/userlist.txt"

: "${LEDGER_DB_PASSWORD:?LEDGER_DB_PASSWORD must be set}"
: "${WALLET_DB_PASSWORD:?WALLET_DB_PASSWORD must be set}"
: "${COMMISSION_DB_PASSWORD:?COMMISSION_DB_PASSWORD must be set}"
: "${TREASURY_DB_PASSWORD:?TREASURY_DB_PASSWORD must be set}"
: "${CASHBACK_DB_PASSWORD:?CASHBACK_DB_PASSWORD must be set}"
: "${SELLERPAYOUT_DB_PASSWORD:?SELLERPAYOUT_DB_PASSWORD must be set}"

cat > "${OUT}" <<EOF
"ledger_admin"      "${LEDGER_DB_PASSWORD}"
"wallet_user"       "${WALLET_DB_PASSWORD}"
"commission_user"   "${COMMISSION_DB_PASSWORD}"
"treasury_user"     "${TREASURY_DB_PASSWORD}"
"cashback_user"     "${CASHBACK_DB_PASSWORD}"
"sellerpayout_user" "${SELLERPAYOUT_DB_PASSWORD}"
EOF

chmod 600 "${OUT}"
echo "pgbouncer-ledger: userlist.txt written (${OUT})"

#!/usr/bin/env bash
# local-walk-seed.sh — bring the local stack to a fully-walkable state on current
# main: schema to head + all seeds + a logged-in test user with cart / favorites /
# addresses / orders (5 statuses) / returns (3 statuses) / coin balance.
#
# DEV ONLY. Reconstructs the never-merged scripts/dev/local-phaseb.sh.
# See docs/internal/local-walk-env.md.
#
# Prereqs: the stack is up (`make run-local`) and healthy. Postgres is internal-
# only, so all DB work goes through `docker exec`. Idempotent — safe to re-run.
#
# Usage:  scripts/dev/local-walk-seed.sh
# Env:    BASE_URL (default http://localhost), WALK_EMAIL, WALK_PASS,
#         ECOM_FROM (default 0083), LEDGER_FROM (default 0080)

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost}"
WALK_EMAIL="${WALK_EMAIL:-walk@mopro.local}"
WALK_PASS="${WALK_PASS:-WalkTest1234!}"
ECOM_FROM="${ECOM_FROM:-0083}"
LEDGER_FROM="${LEDGER_FROM:-0080}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

say() { printf '\033[0;36m▶ %s\033[0m\n' "$*"; }
ecom() { docker exec -i postgres-ecom psql -U ecom_admin -d mopro_ecom "$@"; }
ledg() { docker exec -i postgres-ledger psql -U ledger_admin -d mopro_ledger "$@"; }

say "0. stack health"
curl -fsS -m5 "$BASE_URL/healthz" >/dev/null || { echo "stack not up — run 'make run-local'"; exit 1; }

# 1. Schema → head. The local DB schema comes from deploy/postgres-*/init/*.sql
# (no schema_migrations, no auto-migrate), so migrations added since the volume
# was created are missing. Apply the pending *.up.sql above the known gap. They
# are additive (IF NOT EXISTS / ON CONFLICT), so ON_ERROR_STOP=0 makes re-runs
# (and already-applied files) no-op. For a FRESH volume, prefer `migrate-tool up`.
say "1. applying pending migrations (ecom >= $ECOM_FROM, ledger >= $LEDGER_FROM)"
for f in "$ROOT"/migrations/ecom/*.up.sql; do
  v="$(basename "$f" | cut -d_ -f1)"
  [ "$v" \< "$ECOM_FROM" ] && continue
  ecom -v ON_ERROR_STOP=0 -q < "$f" >/dev/null 2>&1 && echo "  ecom $v ok" || echo "  ecom $v (skipped/partial)"
done
for f in "$ROOT"/migrations/ledger/*.up.sql; do
  v="$(basename "$f" | cut -d_ -f1)"
  [ "$v" \< "$LEDGER_FROM" ] && continue
  ledg -v ON_ERROR_STOP=0 -q < "$f" >/dev/null 2>&1 && echo "  ledger $v ok" || echo "  ledger $v (skipped/partial)"
done

# 2. Catalog seed (Go CLI) is assumed already applied (50 products); re-running it
# is idempotent if you have host DB access. SQL extras are idempotent — apply them.
say "2. applying SQL seed extras (merch / coin / pdp / plp / attr)"
if [ "$(ecom -tAc 'select count(*) from catalog_schema.products' 2>/dev/null | tr -d '[:space:]')" = "0" ]; then
  echo "  !! catalog empty — run 'make seed-staging' with host DB access first"
fi
for f in "$ROOT"/scripts/seed/data/*.sql; do
  ecom -v ON_ERROR_STOP=0 -q < "$f" >/dev/null 2>&1 && echo "  $(basename "$f") ok" || echo "  $(basename "$f") (skipped)"
done

# 3. Authed test user (API: correct bcrypt + PII encryption), then verify in DB
# (no email gate bypass endpoint in dev) and log in.
say "3. test user $WALK_EMAIL"
curl -fsS -m10 -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$WALK_EMAIL\",\"password\":\"$WALK_PASS\",\"name_first\":\"Ayşe\",\"name_last\":\"Yılmaz\",\"locale\":\"tr-TR\"}" \
  >/dev/null 2>&1 && echo "  registered" || echo "  already exists"
ecom -q -c "update identity_schema.users set email_verified=true where email_verified=false;" >/dev/null
AT="$(curl -fsS -m10 -X POST "$BASE_URL/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$WALK_EMAIL\",\"password\":\"$WALK_PASS\"}" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)"
[ -n "$AT" ] || { echo "login failed"; exit 1; }
echo "  logged in (token acquired)"
auth() { curl -fsS -m10 -H "Authorization: Bearer $AT" -H 'Content-Type: application/json' "$@"; }

# 4. Addresses + cart + favorites (API; PII-encrypting paths).
say "4. addresses / cart / favorites (API)"
auth -X POST "$BASE_URL/addresses" -d '{"label":"Ev","name":"Ayşe Yılmaz","phone":"+905551112233","full_address":"Atatürk Cad. No:12 D:3","neighborhood":"Merkez Mah.","district":"Kadıköy","city":"İstanbul","postal_code":"34000","is_default":true}' >/dev/null 2>&1 || true
auth -X POST "$BASE_URL/addresses" -d '{"label":"İş","name":"Ayşe Yılmaz","phone":"+905551112233","full_address":"Levent Plaza Kat:4","neighborhood":"Levent","district":"Beşiktaş","city":"İstanbul","postal_code":"34330","is_default":false}' >/dev/null 2>&1 || true
for v in 2 4 7; do auth -X POST "$BASE_URL/cart/items" -d "{\"variant_id\":$v,\"qty\":1}" >/dev/null 2>&1 || true; done
auth -X POST "$BASE_URL/favorites/sync" -d '{"product_ids":[1,3,5,9]}' >/dev/null 2>&1 || true
echo "  addresses(2) + cart(3 items, multi-seller) + favorites(4)"

# 5. Order/return history + coin (direct SQL — terminal statuses + double-entry the
# API can't set). Idempotent.
say "5. orders (5 statuses) / returns (3 statuses) / coin (SQL)"
ecom -v ON_ERROR_STOP=1 -q < "$HERE/walk-user-data.sql" >/dev/null && echo "  orders + returns + multi-seller spread ok"
ledg -v ON_ERROR_STOP=1 -q < "$HERE/walk-user-coin.sql" >/dev/null && echo "  coin entry ok"

say "DONE — walk creds:  $WALK_EMAIL  /  $WALK_PASS   (base $BASE_URL)"
echo "Launch Flutter:  cd mobile && flutter run --dart-define=API_BASE_URL=$BASE_URL  (TR locale, log in with the creds above)"

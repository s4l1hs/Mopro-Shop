#!/usr/bin/env bash
set -euo pipefail

SCHEMAS="identity|catalog|cart|order|payment|seller|search|wallet|commission|treasury|cashback|shipping|notification|support|media|sizefinder|attachments"

# Cross-module-schema reads in raw SQL (ref_schema is exempt).
# Migrations are exempt because they own the schema and routinely seed
# cross-schema reference rows (e.g. migration 0077_order_capture_postings
# creates commission_schema.capture_postings AND seeds account rows in
# wallet_schema as part of the orderledger setup).
if grep -rE "FROM\s+($SCHEMAS)_schema\." \
    --include='*.sql' --include='*.go' \
    internal/ migrations/ \
    | grep -vE '/(identity|catalog|cart|order|payment|seller|search|wallet|commission|treasury|cashback|sellerpayout|reconcile|shipping|notification|support|media|sizefinder|attachments|eventbus|e2e)/' \
    | grep -vE '^migrations/' \
    | grep -vE 'ref_schema\.' ; then
    echo "ERROR: cross-schema reference detected"
    exit 1
fi

# Float for money
if grep -rE '(float32|float64).*amount' --include='*.go' internal/ ; then
    echo "ERROR: float type used for amount; use BIGINT minor units"
    exit 1
fi

# Direct redis.XAdd outside outbox
if grep -rE 'redis.*XAdd' --include='*.go' internal/ \
    | grep -v internal/eventbus/redis_bus.go \
    | grep -v internal/outbox/publisher.go \
    | grep -v '_test.go' ; then
    echo "ERROR: redis.XAdd outside outbox publisher; route through outbox"
    exit 1
fi

# Hardcoded currency literals in business logic (allow only in seeds/tests/ref readers)
if grep -rE '"(TRY|TRY_COIN|EUR|USD|AED|EUR_COIN|USD_COIN)"' --include='*.go' internal/ \
    | grep -v _test.go \
    | grep -v internal/currency/ \
    | grep -v 'pkg/currency/' ; then
    echo "WARNING: hardcoded currency literal in business logic"
    # not exit 1 yet; warn and let CI decide
fi

# Cashback plan core-field UPDATE attempts (mutable: last_distributed_period, status, updated_at)
if grep -rE 'UPDATE\s+cashback_schema\.plans.*\b(monthly_amount_minor|start_date|currency|reference_interest_rate_bps|delivered_at)\b' \
    --include='*.sql' --include='*.go' internal/ migrations/ ; then
    echo "ERROR: cashback_schema.plans core fields are immutable; use reversal/new plan pattern"
    exit 1
fi

# Seller payout UPDATE attempts (status field allowed; core fields blocked by DB trigger)
if grep -rE 'UPDATE\s+commission_schema\.seller_payouts.*\b(amount_minor|unlock_at|currency|order_id|seller_id)\b' \
    --include='*.sql' --include='*.go' internal/ migrations/ ; then
    echo "ERROR: seller_payouts core fields are immutable; use reversal pattern"
    exit 1
fi

# Hardcoded payback months other than 24 (v5 model)
if grep -rE 'PaybackMonths\s*=\s*(?!24\b)\d+' --include='*.go' internal/cashback/ ; then
    echo "ERROR: cashback PaybackMonths must be 24 (v5 model)"
    exit 1
fi

# Hardcoded calendar-day delay for unlock_at (must use timex.AddBusinessDays)
# e2e tests are exempt: AddDate(0,0,3) there is a lower-bound assertion, not a business rule.
if grep -rE 'deliveredAt\.AddDate\(\s*0\s*,\s*0\s*,\s*3\s*\)' --include='*.go' internal/ \
    | grep -v internal/e2e/ ; then
    echo "ERROR: use timex.AddBusinessDays for the 3-day delay, not calendar-day AddDate"
    exit 1
fi

# Hardcoded commission rates in business logic (must read order_items.commission_pct_bps snapshot)
if grep -rE 'commission_pct_bps\s*[:=]\s*\d+' --include='*.go' internal/ \
    | grep -v _test.go \
    | grep -v internal/commission/ ; then
    echo "WARNING: hardcoded commission_pct_bps; should read from snapshot"
fi

# commission_schema regression guard.
#
# After the commission-owns-capture-postings refactor, capture_postings
# audit-row SQL lives only in internal/commission/ (behind
# commission.CaptureRecorder). This guard fails the build if any future
# code outside the recognized callers re-introduces direct
# commission_schema.* access. Tighter than the generic cross-schema check
# above because it catches every SQL operation (INSERT / UPDATE / DELETE
# / JOIN / REFERENCES), not just FROM.
#
# Recognized callers (exempt):
#   - internal/commission/          — the owner.
#   - internal/sellerpayout/        — owns seller_payouts (table grouped
#                                     into commission_schema by historical
#                                     schema-naming choice; consider
#                                     splitting into sellerpayout_schema
#                                     in a future refactor).
#   - internal/e2e/                 — end-to-end tests routinely span
#                                     schemas to seed and verify state.
#   - migrations/, deploy/postgres-ledger/init/
#                                   — DDL / schema source of truth.
COMMISSION_VIOLATORS=$(grep -rEn 'commission_schema\.[a-z_]+' \
    --include='*.sql' --include='*.go' \
    internal/ migrations/ deploy/postgres-ledger/init/ \
    | grep -vE '^internal/commission/' \
    | grep -vE '^internal/sellerpayout/' \
    | grep -vE '^internal/e2e/' \
    | grep -vE '^migrations/' \
    | grep -vE '^deploy/postgres-ledger/init/' \
    || true)
if [ -n "$COMMISSION_VIOLATORS" ]; then
    echo "ERROR: commission_schema.* access outside the recognized callers" >&2
    echo "$COMMISSION_VIOLATORS" >&2
    echo "Use commission.CaptureRecorder (or add a new commission-owned interface)." >&2
    exit 1
fi

echo "boundaries OK"

#!/usr/bin/env bash
set -euo pipefail

SCHEMAS="identity|catalog|cart|order|payment|seller|search|wallet|commission|treasury|cashback|notification|support|media|sizefinder"

# Cross-module-schema reads in raw SQL (ref_schema is exempt)
if grep -rE "FROM\s+($SCHEMAS)_schema\." \
    --include='*.sql' --include='*.go' \
    internal/ migrations/ \
    | grep -vE '/(identity|catalog|cart|order|payment|seller|search|wallet|commission|treasury|cashback|sellerpayout|notification|support|media|sizefinder|e2e)/' \
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
    | grep -v internal/outbox/publisher.go ; then
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

# Cashback plan UPDATE attempts (must use reversal/new plan instead)
if grep -rE 'UPDATE\s+cashback_schema\.plans' --include='*.sql' --include='*.go' internal/ migrations/ ; then
    echo "ERROR: cashback_schema.plans is immutable; use reversal/new plan pattern"
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

echo "boundaries OK"

# DEVELOPMENT.md — Local Setup, Testing, Pre-Push Checks v7

Reflects PRD v6.0 (perpetual cashback) + v7 detail packs (PSP & kargo API'ları, mobil 30+ ekran, anti-fraud ML, TR e-fatura/e-arşiv/GİB).

---

## 1. Prerequisites

| Tool | Version |
|---|---|
| Go | 1.22+ |
| Docker Engine | 24+ |
| Docker Compose v2 | bundled |
| golangci-lint | 1.55+ |
| restic | 0.16+ (for testing backup paths) |
| Node.js | 20+ |
| Flutter | 3.x |

---

## 2. First-Time Setup

```bash
git clone git@github.com:mopro/platform.git
cd platform
# Create your local .env (see § 3 below for the required variables)
: > .env && chmod 600 .env
./scripts/install-hooks.sh
go mod download
```

---

## 3. .env — Required Variables

NEVER commit `.env`. NEVER copy production values into it.

```bash
# DB passwords — local only
ECOM_DB_PASSWORD=dev_ecom_pw
LEDGER_DB_PASSWORD=dev_ledger_pw
IDENTITY_DB_PASSWORD=dev_identity_pw
CATALOG_DB_PASSWORD=dev_catalog_pw
CART_DB_PASSWORD=dev_cart_pw
ORDER_DB_PASSWORD=dev_order_pw
PAYMENT_DB_PASSWORD=dev_payment_pw
SELLER_DB_PASSWORD=dev_seller_pw
SEARCH_DB_PASSWORD=dev_search_pw
WALLET_DB_PASSWORD=dev_wallet_pw
COMMISSION_DB_PASSWORD=dev_commission_pw
TREASURY_DB_PASSWORD=dev_treasury_pw
CASHBACK_DB_PASSWORD=dev_cashback_pw
SELLERPAYOUT_DB_PASSWORD=dev_sellerpayout_pw
NOTIFICATION_DB_PASSWORD=dev_notification_pw
SUPPORT_DB_PASSWORD=dev_support_pw
MEDIA_DB_PASSWORD=dev_media_pw
SIZEFINDER_DB_PASSWORD=dev_sizefinder_pw

# Redis
REDIS_PASSWORD=dev_redis_pw

# Meilisearch
MEILI_MASTER_KEY=dev_meili_master_key

# Caddy
CADDY_EMAIL=dev@localhost

# JWT
JWT_SIGNING_KEY=dGhpc2lzYWRldnNpZ25pbmdrZXktMzJieXRlcw==

# PII encryption
PII_KEK_BASE64=YjY0LWVuY29kZWQta2VrLTMyYnl0ZXMtZm9yLWFlcy1nY20=
PII_PEPPER=dev-pepper-not-for-prod

# Market & Localization (TR launch defaults)
MARKET=TR
DEFAULT_CURRENCY=TRY
DEFAULT_LOCALE=tr-TR
DATA_REGION=eu-central-1

# Coin issuance jurisdiction (filled in once licensed)
COIN_LICENSE_JURISDICTION=          # 'AE-DXB' | 'LT' | 'EE' | 'MT' | empty=pre-license
COIN_LICENSE_AUTHORITY=             # 'VARA' | 'B-EMI' | 'EFSA' | 'MFSA' | empty

# Cashback parameters — v5 LOCKED MODEL (do NOT change in env; constitution-level)
# v6: Plan is perpetual; reference rate is 5000 bps (%50) hardcoded as cashback.ReferenceInterestRateBpsConst
# Cashback total = sum(order_items.commission_amount_minor) read from snapshot

# Seller payout parameters — v5 LOCKED MODEL
# Delay = 3 business days (hardcoded const sellerpayout.PayoutDelayBusinessDays)

# PSP (sandbox creds in dev)
PSP_PROVIDER=sipay                  # sipay | craftgate | iyzico (TR launch)
                                    # stripe | mollie | adyen (EU, Phase 7+)
PSP_API_KEY=sandbox_xxx
PSP_SECRET=sandbox_xxx
PSP_MERCHANT_ID=sandbox_xxx
PSP_WEBHOOK_SECRET=sandbox_xxx

# Shipping providers (TR launch)
SHIPPING_DEFAULT=aras               # aras | yurtici | surat | mng | hepsijet | ptt
ARAS_API_KEY=sandbox_xxx
YURTICI_API_KEY=sandbox_xxx
# ... per provider

# Backblaze B2 (optional in dev; use minio for fully offline)
B2_KEY_ID=
B2_APP_KEY=
RESTIC_PASSWORD=

# Grafana Cloud (optional in dev)
GRAFANA_PROM_USER=
GRAFANA_PROM_PASS=
GRAFANA_LOKI_USER=
GRAFANA_LOKI_PASS=
GRAFANA_TEMPO_USER=
GRAFANA_TEMPO_PASS=

# Healthchecks (optional in dev)
HEALTHCHECK_BACKUP_UUID=
HEALTHCHECK_RESTORE_UUID=
HEALTHCHECK_DISK_HYGIENE_UUID=
HEALTHCHECK_LEDGER_RECONCILE_UUID=
HEALTHCHECK_CASHBACK_CRON_UUID=
HEALTHCHECK_SELLER_PAYOUT_CRON_UUID=

# Slack/PagerDuty (optional in dev — leave blank to disable alerts)
SLACK_WEBHOOK=
SLACK_PANIC_WEBHOOK=
PAGERDUTY_API=
BETTERSTACK_INCIDENT_API=

# Admin internal token (for cron-to-fin-svc admin endpoints)
ADMIN_INTERNAL_TOKEN=dev_admin_token
```

---

## 4. Bring Up the Local Stack

```bash
docker compose --env-file .env up -d
docker compose --env-file .env logs -f core-svc
docker compose --env-file .env logs -f fin-svc
curl -sf http://localhost/healthz
docker compose down       # preserve volumes
docker compose down -v    # WIPE volumes (carefully)
```

---

## 5. Iterating on a Single Binary

```bash
docker compose stop core-svc
export $(grep -v '^#' .env | xargs)
go run ./cmd/core-svc
```

---

## 6. Database Tools

```bash
docker exec -it postgres-ecom psql -U ecom_admin -d mopro_ecom
docker exec -it postgres-ledger psql -U ledger_admin -d mopro_ledger
go run ./cmd/migrate-tool ecom up
go run ./cmd/migrate-tool ledger up

# Reset (DEV ONLY — wipes data)
docker compose down
sudo rm -rf data/postgres-ecom data/postgres-ledger
docker compose up -d postgres-ecom postgres-ledger
```

After applying migrations the first time, the seed of `ref_schema.commission_rules` (42 categories) and `ref_schema.business_calendars` (TR holidays 2026-2030) populate automatically. Verify with:

```sql
SELECT count(*) FROM ref_schema.commission_rules WHERE market='TR';  -- expect 42
SELECT count(*) FROM ref_schema.business_calendars WHERE market='TR';  -- expect ~50 (2026-2030)
```

---

## 7. Testing Standards

### 7.1 Unit tests

```bash
go test ./...
go test -race ./...
go test -cover ./...
```

Coverage minimum: 70% per module. fin-svc modules: 85% (wallet, commission, treasury, **cashback**, **sellerpayout**).

### 7.2 Property-Based Tests — MANDATORY for ledger AND cashback AND sellerpayout

Any change to `wallet`, `commission`, `treasury`, `cashback`, or `sellerpayout` MUST add or extend property tests with `gopter`.

#### Ledger property: per-currency D=C invariant

```go
// /internal/wallet/property_test.go
package wallet_test

import (
    "reflect"
    "testing"
    "github.com/leanovate/gopter"
    "github.com/leanovate/gopter/gen"
    "github.com/leanovate/gopter/prop"
)

type Op struct {
    Type     string
    Account  int64
    Amount   int64
    Currency string
}

func genOp() gopter.Gen {
    return gen.Struct(reflect.TypeOf(Op{}), map[string]gopter.Gen{
        "Type":     gen.OneConstOf("commission", "withdraw", "reversal", "cashback_payment", "seller_payout"),
        "Account":  gen.Int64Range(1, 100),
        "Amount":   gen.Int64Range(1, 100_000_00),
        "Currency": gen.OneConstOf("TRY", "TRY_COIN"),
    })
}

func TestProperty_LedgerStaysBalanced_PerCurrency(t *testing.T) {
    params := gopter.DefaultTestParameters()
    params.MinSuccessfulTests = 1000
    properties := gopter.NewProperties(params)

    properties.Property("Per-currency Sum(D) - Sum(C) is always 0", prop.ForAll(
        func(ops []Op) bool {
            db := setupTestLedger(t)
            for _, op := range ops {
                applyOp(t, db, op)  // each op posts a single-currency tx
            }
            // Check each currency independently
            for _, cur := range []string{"TRY", "TRY_COIN"} {
                if totalDelta(db, cur) != 0 {
                    return false
                }
            }
            return true
        },
        gen.SliceOf(genOp()),
    ))
    properties.TestingRun(t)
}
```

#### Cashback property (v6 PERPETUAL): exact monthly amount preservation across N periods

```go
// /internal/cashback/property_test.go
package cashback_test

import (
    "reflect"
    "testing"
    "github.com/leanovate/gopter"
    "github.com/leanovate/gopter/gen"
    "github.com/leanovate/gopter/prop"
)

func TestProperty_CashbackPaymentsSumToPlanTotal(t *testing.T) {
    params := gopter.DefaultTestParameters()
    params.MinSuccessfulTests = 500
    properties := gopter.NewProperties(params)

    properties.Property("After all 24 monthly payments, user wallet credited exactly plan.total_amount_minor", prop.ForAll(
        func(orderPriceMinor int64, commissionPctBps int) bool {
            if commissionPctBps == 0 || orderPriceMinor == 0 { return true }
            db := setupTestLedger(t)
            engine := setupCashbackEngine(t, db)

            cashbackTotal := orderPriceMinor * int64(commissionPctBps) / 10000
            plan, _ := engine.CreatePlanForOrder(ctx, OrderEvent{
                Items: []OrderItem{{
                    UnitPriceMinor:        orderPriceMinor,
                    Qty:                   1,
                    CommissionPctBps:      commissionPctBps,
                    CommissionAmountMinor: cashbackTotal,
                }},
                DeliveredAt: time.Now(),
                Market:      "TR",
            })

            // Simulate paying every month (24 in v5)
            for m := 1; m <= 24; m++ {
                engine.PayMonthForPlan(ctx, plan.ID, m)
            }

            walletBalance := getUserWalletBalance(db, plan.UserID, plan.Currency)
            return walletBalance == cashbackTotal
        },
        gen.Int64Range(100, 1_000_000_00),     // 1 TL to 1M TL
        gen.IntRange(500, 2000),                // 5% to 20% commission
    ))
    properties.TestingRun(t)
}

func TestProperty_PlanIsImmutableAfterCreation(t *testing.T) {
    properties := gopter.NewProperties(nil)
    properties.Property("UPDATE on plan core fields raises", prop.ForAll(
        func(orderID int64, newAmount int64) bool {
            db := setupTestLedger(t)
            engine := setupCashbackEngine(t, db)
            plan, _ := engine.CreatePlanForOrder(ctx, OrderEvent{
                OrderID: orderID,
                Items: []OrderItem{{CommissionAmountMinor: 200_00}},
                DeliveredAt: time.Now(), Market: "TR",
            })
            // Try to mutate (should error)
            _, err := db.Exec(ctx, `
                UPDATE cashback_schema.plans
                SET monthly_amount_minor = $1
                WHERE id = $2`, newAmount, plan.ID)
            return err != nil  // expect error
        },
        gen.Int64Range(1, 1000),
        gen.Int64Range(1, 999_999),
    ))
    properties.TestingRun(t)
}
```

#### Seller payout property: unlock_at = AddBusinessDays(delivered_at, 3, calendar)

```go
// /internal/sellerpayout/property_test.go
package sellerpayout_test

func TestProperty_PayoutUnlockIsThreeBusinessDays(t *testing.T) {
    properties := gopter.NewProperties(nil)
    properties.Property("unlock_at always equals AddBusinessDays(delivered_at, 3, TR_calendar)", prop.ForAll(
        func(deliveredYear, deliveredMonth, deliveredDay int) bool {
            deliveredAt := time.Date(deliveredYear, time.Month(deliveredMonth), deliveredDay, 12, 0, 0, 0, time.UTC)
            engine := setupPayoutEngine(t, db)
            payout, _ := engine.SchedulePayoutForOrder(ctx, OrderEvent{
                OrderID: 1, DeliveredAt: deliveredAt, Market: "TR",
                Items: []OrderItem{{SellerNetMinor: 100_00, SellerID: 42}},
            })
            expected := timex.AddBusinessDays(deliveredAt, 3, trCalendar)
            return payout.UnlockAt.Equal(expected.Truncate(24 * time.Hour))
        },
        gen.IntRange(2026, 2030), gen.IntRange(1, 12), gen.IntRange(1, 28),
    ))
    properties.TestingRun(t)
}
```

CI fails if missing/failing.

### 7.3 Integration tests

```bash
go test -tags=integration ./...
```

Integration tests spin up a fresh Postgres + Redis via testcontainers-go. Hermetic.

For cashback integration tests:
```bash
go test -tags=integration -run TestCashback ./internal/cashback/...
```

These tests:
1. Spin up postgres-ledger.
2. Apply migrations.
3. Simulate `ecom.order.delivered.v1` events.
4. Verify plans + payments are correctly created at delivered+3BD.
5. Verify the plan is FROZEN (UPDATE attempts fail).
6. Run the monthly cron in fast-forward mode 24 times.
7. Verify user wallet ends up with exact total cashback (commission_amount_minor sum).

For seller payout integration tests:
```bash
go test -tags=integration -run TestSellerPayout ./internal/sellerpayout/...
```

These tests:
1. Spin up postgres-ledger + a mock PSP server.
2. Apply migrations.
3. Simulate `ecom.order.delivered.v1` with multi-seller items.
4. Verify one payout per (order, seller) tuple.
5. Verify `unlock_at` = delivered + 3 BD using TR calendar.
6. Verify the payout is FROZEN.
7. Run the daily cron at unlock_at; verify ledger move + PSP transfer.
8. Simulate PSP webhook confirmation; verify status transitions to `paid`.

---

## 8. Pre-Push Verification

Run before every `git push`:

```bash
make verify
```

```makefile
.PHONY: verify fmt vet test lint boundaries property-cashback property-payout property-ledger

verify: fmt vet test lint boundaries property-cashback property-payout property-ledger

fmt:
	gofmt -l . | tee /tmp/gofmt.out
	test ! -s /tmp/gofmt.out

vet:
	go vet ./...

test:
	go test -race ./...

lint:
	golangci-lint run

boundaries:
	./scripts/check-module-boundaries.sh

property-cashback:
	go test -tags=integration -run Property ./internal/cashback/...

property-payout:
	go test -tags=integration -run Property ./internal/sellerpayout/...

property-ledger:
	go test -tags=integration -run Property ./internal/wallet/...
```

`scripts/install-hooks.sh` wires `make verify` into pre-push.

---

## 9. Module Boundary Linter

`.golangci.yml` (excerpt):

```yaml
linters:
  enable: [depguard, gocyclo, errcheck, revive, gosec, gocritic]

linters-settings:
  depguard:
    rules:
      core-modules-no-fin:
        list-mode: lax
        files:
          - "internal/identity/**"
          - "internal/catalog/**"
          - "internal/cart/**"
          - "internal/order/**"
          - "internal/payment/**"
          - "internal/seller/**"
          - "internal/search/**"
        deny:
          - pkg: github.com/mopro/platform/internal/wallet
            desc: "core-svc modules MUST NOT import fin-svc internals; use eventbus"
          - pkg: github.com/mopro/platform/internal/commission
            desc: "core-svc modules MUST NOT import fin-svc internals; use eventbus"
          - pkg: github.com/mopro/platform/internal/treasury
            desc: "core-svc modules MUST NOT import fin-svc internals; use eventbus"
          - pkg: github.com/mopro/platform/internal/cashback
            desc: "core-svc modules MUST NOT import fin-svc internals; use eventbus"
          - pkg: github.com/mopro/platform/internal/sellerpayout
            desc: "core-svc modules MUST NOT import fin-svc internals; use eventbus"
      fin-no-ecom:
        files:
          - "internal/wallet/**"
          - "internal/commission/**"
          - "internal/treasury/**"
          - "internal/cashback/**"
          - "internal/sellerpayout/**"
        deny:
          - pkg: github.com/mopro/platform/internal/order
            desc: "fin-svc MUST NOT import core-svc internals"
          - pkg: github.com/mopro/platform/internal/payment
            desc: "fin-svc MUST NOT import core-svc internals"
      cashback-uses-wallet-via-public-api:
        files:
          - "internal/cashback/**"
          - "internal/sellerpayout/**"
        deny:
          - pkg: github.com/mopro/platform/internal/wallet/repository
            desc: "Use wallet public Service interface, not internal repository"
      modules-only-via-api:
        files:
          - "internal/order/**"
        deny:
          - pkg: github.com/mopro/platform/internal/catalog/repository
            desc: "Use internal/catalog public interface"
          - pkg: github.com/mopro/platform/internal/catalog/service
            desc: "Use internal/catalog public interface"
```

---

## 10. `scripts/check-module-boundaries.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCHEMAS="identity|catalog|cart|order|payment|seller|search|wallet|commission|treasury|cashback|notification|support|media|sizefinder"

# Cross-module-schema reads in raw SQL (ref_schema is exempt)
if grep -rE "FROM\s+($SCHEMAS)_schema\." \
    --include='*.sql' --include='*.go' \
    internal/ migrations/ \
    | grep -vE '/(identity|catalog|cart|order|payment|seller|search|wallet|commission|treasury|cashback|sellerpayout|notification|support|media|sizefinder)/' \
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
if grep -rE 'deliveredAt\.AddDate\(\s*0\s*,\s*0\s*,\s*3\s*\)' --include='*.go' internal/ ; then
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
```

---

## 11. CI/CD Local Mirror

```bash
make verify
docker buildx build -t local/core-svc -f build/Dockerfile --build-arg SERVICE=core-svc .
trivy image --severity HIGH,CRITICAL local/core-svc
```

---

## 12. Common Tasks Cheat Sheet

```bash
# Add a Go module skeleton
./scripts/new-module.sh internal/<name>

# Generate event payload types
go generate ./internal/eventbus/...

# Tail logs and grep for trace_id
docker compose logs -f --no-color | grep '"trace_id":"abc123"'

# Inspect Redis Streams
docker exec redis redis-cli -a "$REDIS_PASSWORD" XINFO STREAM ecom.order.delivered.v1

# Check pending outbox
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
  "SELECT count(*) FROM order_schema.outbox WHERE published_at IS NULL"

# Cashback dev helpers
mopro cashback inspect 1
mopro cashback list-due --month 2026-06 --dry-run
mopro cashback obligation-check

# Seller payout dev helpers (v5)
mopro payout inspect 1
mopro payout list-due --date 2026-05-15 --dry-run
mopro payout obligation-check

# Business calendar inspection
mopro calendar show TR --year 2026
```

---

## 13. Editor Configuration

`.vscode/settings.json` (project-scoped):

```json
{
  "go.useLanguageServer": true,
  "go.lintTool": "golangci-lint",
  "go.lintFlags": ["--fast"],
  "[go]": { "editor.formatOnSave": true }
}
```

---

## 14. Code Style

- `gofmt`-clean. No exceptions.
- Errors are values; wrap with `fmt.Errorf("...: %w", err)`.
- No `panic` except for unrecoverable startup faults.
- Context as first arg for IO-bound functions.
- Tests live as `<thing>_test.go`.
- Public APIs documented with godoc starting with the symbol name.

---

## 15. Internationalization Rules

- NO hardcoded user-facing strings in any Go HTTP response or Flutter widget. Use translation keys.
- NO hardcoded currency codes outside `ref_schema` seeds and config files. Pass currency as a parameter.
- NO hardcoded locale formatting (date, number, phone). Use intl/locale-aware libraries.
- NO hardcoded business-day calendars. Read from `ref_schema.business_calendars` for the active market.
- ALL emails, push notifications, SMS templates live in `/templates/<locale>/<channel>/<event>.tmpl`. Picking the locale is a function of the user's stored locale field.
- Cashback notifications: `/templates/<locale>/push/cashback_payment_posted.tmpl` ("Bu ay X Mopro Coin kazandın!" in Turkish, "You earned X Mopro Coin this month!" in English).
- Seller payout notifications: `/templates/<locale>/{push,email}/seller_payout_posted.tmpl`.
- Database queries that filter by user-facing text MUST go through normalized columns (lowercased + collation-aware).

---

## 17. Sipay Sandbox Onboarding & Webhook Tunneling

### 17.1 Getting Sipay Sandbox Credentials

1. Register a sandbox merchant account at `https://sipay.com.tr/uye-isyeri-basvurusu`.
2. Sipay support will email four sandbox values:
   - `SIPAY_APP_ID`
   - `SIPAY_APP_SECRET`
   - `SIPAY_MERCHANT_ID`
   - `SIPAY_MERCHANT_KEY`
3. The sandbox base URL is `https://provisioning.sipay.com.tr/ccpayment` (confirm with Sipay support — it may differ for sandbox vs. production).
4. Add the following to `.env` (never commit this file):

```bash
PSP_PROVIDER=sipay
SIPAY_BASE_URL=https://provisioning.sipay.com.tr
SIPAY_APP_ID=<your_sandbox_app_id>
SIPAY_APP_SECRET=<your_sandbox_app_secret>
SIPAY_MERCHANT_ID=<your_sandbox_merchant_id>
SIPAY_MERCHANT_KEY=<your_sandbox_merchant_key>
SIPAY_RETURN_URL=https://<your-tunnel-subdomain>/api/payment/return
SIPAY_CANCEL_URL=https://<your-tunnel-subdomain>/api/payment/cancel
```

> **D2 guard**: If `GO_ENV=production` is set, the adapter rejects `SIPAY_MERCHANT_KEY` values
> beginning with `test_` or `sandbox_`. Never set `GO_ENV=production` in your local `.env`.

---

### 17.2 Exposing the Webhook Endpoint Locally

Sipay's 3DS callback and webhook POST are sent by Sipay's servers to your `SIPAY_RETURN_URL`.
For local development you need a public HTTPS URL that forwards to `localhost:8080`.

#### Option A — Cloudflare Tunnel (Recommended)

Cloudflare Tunnel is free, persistent, and does not require a paid ngrok account.

```bash
# Install cloudflared (macOS)
brew install cloudflare/cloudflare/cloudflared

# One-time login (browser opens)
cloudflared tunnel login

# Create a named tunnel
cloudflared tunnel create mopro-dev

# Start the tunnel — forwards tunnel URL → localhost:8080
cloudflared tunnel run --url http://localhost:8080 mopro-dev
```

The tunnel prints a public URL like `https://mopro-dev.abc123.trycloudflare.com`.
Set this as `SIPAY_RETURN_URL` and `SIPAY_CANCEL_URL` base in `.env`.

Sipay webhook URL to register in the Sipay merchant portal:
```
https://mopro-dev.abc123.trycloudflare.com/webhooks/sipay
```

#### Option B — ngrok

```bash
# Install ngrok (macOS)
brew install ngrok

# Authenticate (free tier — requires account)
ngrok config add-authtoken <your_ngrok_authtoken>

# Start tunnel
ngrok http 8080
```

ngrok prints a URL like `https://abc123.ngrok-free.app`. Use this as the base.

> **Note**: ngrok free tier URLs change on each restart. Cloudflare Tunnel with a named tunnel
> is preferred for persistent local development — the URL stays stable across restarts.

---

### 17.3 Registering the Webhook in the Sipay Portal

1. Log in to the Sipay merchant portal.
2. Navigate to **Settings → Webhook / Notification URL**.
3. Enter your tunnel webhook URL:
   ```
   https://<tunnel-subdomain>/webhooks/sipay
   ```
4. Save. Sipay will send a test POST to verify reachability.

---

### 17.4 Running the Sandbox Integration Tests

Real-network sandbox tests are gated behind the `sipay_sandbox` build tag.

```bash
# Only runs when SIPAY_APP_ID is set and sipay_sandbox tag is present.
SIPAY_APP_ID=<sandbox> SIPAY_APP_SECRET=<secret> \
  go test -tags=sipay_sandbox -v ./internal/payment/sipay/...
```

Mock-only httptest integration tests (no credentials needed):
```bash
go test -tags=integration -v ./internal/payment/sipay/...
```

---

### 17.5 Verifying Webhook Signature Locally

Use `curl` to send a synthetic Sipay webhook and verify the 3-layer dedup:

```bash
# Compute the expected hash_key manually:
# base64( SHA-512( merchant_key + status_code + invoice_id + total_amount + currency_code ) )

# Send a synthetic captured webhook
curl -s -X POST http://localhost:8080/payments/webhook/sipay \
  -H "Content-Type: application/json" \
  -d '{
    "status_code": 100,
    "invoice_id": "test-idem-key",
    "order_no": "sipay-test-123",
    "total_amount": "5000",
    "currency_code": "TRY",
    "hash_key": "<computed_hash_key>"
  }'
# Expected: HTTP 200
# Second identical POST: HTTP 200 (Redis fast-path dedup)
```

---

## 18. Dev Stack Re-Initialization (After Adding New Migrations)

Migration files in `deploy/postgres/init-ecom/` and `deploy/postgres/init-ledger/` only run
automatically when their respective Docker volume is **empty** (i.e., on first `docker compose up`).
If the stack was already running when new migrations were added, apply them manually using one of
the two options below.

### Option A — Apply without data loss (preferred)

Apply a specific migration file to the running container:

```bash
# Replace filenames with the actual migration(s) to apply.
docker exec -i postgres-ecom \
  psql -U ecom_admin -d mopro_ecom \
  < deploy/postgres-ecom/init/65-order-schema.sql

docker exec -i postgres-ecom \
  psql -U ecom_admin -d mopro_ecom \
  < deploy/postgres-ecom/init/70-payments.sql

# Verify the tables were created:
docker exec postgres-ecom \
  psql -U ecom_admin -d mopro_ecom -c "\dt order_schema.*"
```

Repeat the pattern for ledger migrations (`postgres-ledger` / `ledger_admin` / `mopro_ledger`,
migrations live in `deploy/postgres-ledger/init/`).

### Option B — Full teardown (destroys all dev data)

Use when you want a clean slate or are debugging schema conflicts.

```bash
# Stop all containers AND delete all named volumes.
docker compose -f deploy/docker-compose.yml down -v

# Re-apply all init scripts from scratch on next start.
docker compose -f deploy/docker-compose.yml up -d
```

**Warning:** `-v` permanently deletes all Postgres and Redis data. Use Option A unless you
intentionally want to reset.

---

## 16. fin-svc HTTP API — Known Limitations (Phase 4.3a)

### CashbackPlan.product_id = 0 means "data unavailable"

`cashback_schema.plans` does not yet store product information (product_id, product_title, product_image_url). Phase 4.3a returns the following fallback values in the `GET /cashback/plans` and `GET /cashback/plans/{id}` responses:

| Field | Phase 4.3a value | Production value (Phase 4.3b+) |
|---|---|---|
| `product_id` | `0` | Real product ID from order |
| `product_title` | `"Sipariş #<orderID>"` | Actual product title |
| `product_image_url` | `null` | CDN URL |

Mobile clients MUST treat `product_id == 0` as "product data not yet available" and render the `product_title` fallback string as-is. Do NOT treat `product_id=0` as a real product lookup.

Phase 4.3b will add a DB migration to `cashback_schema.plans` to store product fields, populated via the `ecom.order.delivered.v1` event enrichment path.

### WalletTransaction.reference_id

`transactions.reference` was not set for cashback payments created before Phase 4.3a (fix committed in commit 3 of this phase). Historic payments will have `reference_id=null` in the API response. New payments will have `reference_id=<plan_id>`.

---

## 17. When in Doubt

Read in this order:
1. `CLAUDE.md` — non-negotiable rules (§16 above now lists the Repository-direct exception for HTTP read handlers)
2. `ARCHITECTURE.md` — topology
3. `DATA_DICTIONARY.md` — DB rules
4. `LEDGER_GUIDE.md` — financial rules (if touching fin-svc, wallet, cashback, sellerpayout, treasury)
5. `INFRASTRUCTURE.md` — resource limits
6. `DISASTER_RECOVERY.md` — operational runbooks
7. `PROMPTS.md` — workflow templates
8. This file — local dev

If still unclear: STOP and ask the human owner.

---

## 19. Naming Authority Rule

**Code is the source of truth for event type strings, consumer group names, and stream
topic constants. Documentation must match the code, never the other way around.**

When renaming an event type or consumer group:

1. Rename the constant in the producing module's code first.
2. Rename the constant in every consuming module's code in the same commit or the
   immediately following commit.
3. Update `internal/eventbus/registry.go` in the same commit — mark the old name
   as `StatusDeprecatedPendingDelete` and add the new name as the active entry.
4. Update all documentation (ARCHITECTURE.md, LEDGER_GUIDE.md, PROMPTS.md) in the
   same commit. A documentation-only rename with no code change is FORBIDDEN.
5. If the old stream already has messages in PEL on any consumer group, the group must
   drain (XACK all PEL entries) before the old name is deleted from the registry.

**Never update docs to a name that does not yet exist in code.**

---

## OpenAPI Contract and Codegen (Phase 4.0)

### OpenAPI contract authority rule

`api/openapi.yaml` is the **single source of truth** for all HTTP API shapes.
Generated files (`internal/api/gen/`, `mobile/packages/mopro_api/`) are derived
artifacts and must never be edited by hand.

**When editing the spec:**
1. Make changes in `api/openapi.yaml`.
2. Run `make api-gen` to regenerate all outputs.
3. Commit the spec and ALL generated files in the same commit.
4. The pre-commit hook at `.githooks/pre-commit` enforces step 3.

Activate the hook once per clone:

```bash
git config core.hooksPath .githooks
```

### Generating API stubs

```bash
# Regenerate Go types + server stubs (requires Go 1.22+)
make api-gen-models   # → internal/api/gen/types/types.gen.go
make api-gen-core     # → internal/api/gen/core/server.gen.go
make api-gen-fin      # → internal/api/gen/fin/server.gen.go

# Regenerate Dart client (requires Docker)
make api-gen-dart     # → mobile/packages/mopro_api/

# Regenerate everything at once
make api-gen

# Lint the spec (0 errors required)
make api-lint

# Run contract tests (spec internal-consistency, not live handler tests)
make contract-test
```

Tool versions are pinned in the Makefile:
- `oapi-codegen`: `OAPI_CODEGEN_VERSION = v2.4.1`
- `openapi-generator-cli` (Docker): `OPENAPI_GEN_VERSION = v7.10.0`

### Identity service — OTP and JWT (Phase 4.2a, live)

`X-Mopro-User-Id` header auth bypass has been **removed** in Phase 4.2a.
All authenticated endpoints now require a Bearer JWT issued by the identity service.

#### OTP flow in development

Set `SMS_PROVIDER=mock` (default in `.env`). The mock provider logs the
6-digit OTP to stdout at INFO level — no SMS is sent:

```
core-svc  | level=INFO msg="identity: sms mock" to=+905321234567 code=482915
```

To get the code during a local test:

```bash
docker compose logs core-svc 2>&1 | grep "sms mock"
```

#### DEV_OTP_ACCEPT_ANY backdoor

For automated local testing where you cannot read logs mid-request, set:

```bash
DEV_OTP_ACCEPT_ANY=true  # .env only — NEVER production
ENV=development           # must NOT be "production"
```

When `DEV_OTP_ACCEPT_ANY=true`, `POST /auth/otp/verify` accepts **any** 6-digit
code for any phone. The service panics at startup if this env is set together with
`ENV=production`. This guard is tested in `TestDevOTPAcceptAny_PanicsOnProduction`.

**Do NOT ship `DEV_OTP_ACCEPT_ANY=true` in any Docker image or compose file.**
The CI pipeline enforces `ENV=production` for the build stage, which will cause
a startup panic and fail the deployment.

#### Running the full auth smoke test locally

```bash
# 1. Start the stack
docker compose --env-file .env up -d

# 2. Request OTP (mock SMS — code in logs)
curl -s -X POST http://localhost/auth/otp/request \
  -H "Content-Type: application/json" \
  -d '{"phone":"+905321234567","purpose":"login"}' | jq

# 3. Grab code from logs
CODE=$(docker compose logs core-svc 2>&1 | grep "sms mock" | tail -1 | grep -oP '"code":"\K[0-9]{6}')

# 4. Verify OTP — get token pair
TOKEN_PAIR=$(curl -s -X POST http://localhost/auth/otp/verify \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"+905321234567\",\"purpose\":\"login\",\"code\":\"$CODE\"}")
ACCESS=$(echo $TOKEN_PAIR | jq -r .access_token)

# 5. GET /me
curl -s -H "Authorization: Bearer $ACCESS" http://localhost/me | jq
```

#### Migration convention for identity

Identity tables live in `identity_schema` on `postgres-ecom`. Apply with:

```bash
go run ./cmd/migrate-tool --db ecom up
```

The migration file `migrations/ecom/0055_identity_schema_up.sql` creates four tables:
`users`, `otp_codes`, `refresh_tokens`, `devices`. The `touch_updated_at` trigger
auto-updates `users.updated_at` on any row change.

#### Testutil helpers for other packages

When writing tests for handlers that require a Bearer token, use:

```go
import "github.com/mopro/platform/internal/identity/testutil"

token := testutil.IssueTestAccessToken(t, 42, "TR")
req.Header.Set("Authorization", "Bearer "+token)
```

Do NOT set `X-Mopro-User-Id` in new tests — that header is no longer accepted.

### CI: OpenAPI contract workflow

`.github/workflows/openapi-ci.yml` runs four jobs on any change under `api/`,
`internal/api/`, or `mobile/packages/mopro_api/`:

| Job | What it checks |
|---|---|
| `lint-spec` | Spectral lint — 0 errors |
| `generated-sync` | Re-generates and diffs; fails if committed files don't match |
| `go-build` | Builds all 3 binaries + unit tests (race) + contract tests |
| `dart-analyze` | `flutter pub get` → `build_runner` → `flutter analyze` |

All four jobs must be green before merging to `main`.

---

### Backup pipeline (Phase 5.3)

Nightly restic backups to B2 (primary) + Hetzner (secondary). Weekly restore drill every Sunday.

**Local test (no VDS needed):**
```bash
# Requires restic (brew install restic / apt install restic)
bash deploy/scripts/backup-test.sh

# Fast mode (skips multi-snapshot retention test):
bash deploy/scripts/backup-test.sh --fast
```

Expected output: `Results: N passed, 0 failed`

**Production install (one-shot, run as root on VDS):**
```bash
# Ensure RESTIC_PASSWORD, B2_KEY_ID, B2_APP_KEY, B2_BUCKET are in /opt/mopro/.env
sudo bash /opt/mopro/deploy/scripts/install-backup.sh
```

**Manual backup run:**
```bash
sudo -u mopro bash /opt/mopro/deploy/scripts/backup-postgres.sh
```

**Check snapshots:**
```bash
RESTIC_PASSWORD=$(grep RESTIC_PASSWORD /opt/mopro/.env | cut -d= -f2) \
B2_ACCOUNT_ID=$(grep B2_KEY_ID /opt/mopro/.env | cut -d= -f2) \
B2_ACCOUNT_KEY=$(grep B2_APP_KEY /opt/mopro/.env | cut -d= -f2) \
    restic -r "b2:$(grep B2_BUCKET /opt/mopro/.env | cut -d= -f2):mopro-backups" snapshots
```

**Manual restore:**
```bash
sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
    --db ecom --snapshot latest --confirm YES
```

**Run restore drill manually:**
```bash
sudo -u mopro bash /opt/mopro/deploy/scripts/restore-drill.sh
```

See `docs/runbooks/restore-from-backup.md` for the full DR procedure.

---

### Disk-watch monitor (Phase 5.2)

`deploy/scripts/disk-watch.sh` runs every 60 s via `disk-watch.timer` on the
production VDS. It monitors root filesystem usage and escalates through five
threshold levels:

| Threshold | Action |
|---|---|
| ≥ 70 % | INFO log to `/var/log/disk-watch.log` |
| ≥ 80 % | WARN log + Slack ping |
| ≥ 85 % | WARN log + Slack + PagerDuty warning |
| ≥ 90 % | ERROR log + Slack + PD error + `docker image prune -f` |
| ≥ 92 % | PANIC log + `docker container prune` + log truncation + Redis `SET panic:disk_full 1` |
| Recovery < 80 % | Redis `DEL panic:disk_full` + PD resolve (automatic) |

**Checkout impact:** `POST /checkout/initiate` returns HTTP 503 while
`panic:disk_full = 1` in Redis. All other endpoints and financial crons are
unaffected. The check uses a 100 ms timeout and fails open (Redis unavailable
→ checkout proceeds normally).

**NEVER** use `docker volume prune` — it destroys postgres data volumes.

```bash
# Install on the VDS (run as root, once after first deploy)
sudo bash /opt/mopro/deploy/scripts/install-disk-watch.sh

# Run tests locally (mocks all external calls)
bash deploy/scripts/disk-watch-test.sh

# View timer status
systemctl status disk-watch.timer
journalctl -u mopro-disk-watch -n 50 --no-pager

# Check current panic flag
redis-cli -h redis -p 6379 GET panic:disk_full
```

---

**End of DEVELOPMENT.md.**

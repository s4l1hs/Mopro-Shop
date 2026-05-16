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
cp .env.example .env.local
chmod 600 .env.local
./scripts/install-hooks.sh
go mod download
```

---

## 3. .env.local — Required Variables

NEVER commit `.env.local`. NEVER copy production values into it.

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
docker compose --env-file .env.local up -d
docker compose --env-file .env.local logs -f core-svc
docker compose --env-file .env.local logs -f fin-svc
curl -sf http://localhost/healthz
docker compose down       # preserve volumes
docker compose down -v    # WIPE volumes (carefully)
```

---

## 5. Iterating on a Single Binary

```bash
docker compose stop core-svc
export $(grep -v '^#' .env.local | xargs)
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
4. Add the following to `.env.local` (never commit this file):

```bash
PSP_PROVIDER=sipay
SIPAY_BASE_URL=https://provisioning.sipay.com.tr
SIPAY_APP_ID=<your_sandbox_app_id>
SIPAY_APP_SECRET=<your_sandbox_app_secret>
SIPAY_MERCHANT_ID=<your_sandbox_merchant_id>
SIPAY_MERCHANT_KEY=<your_sandbox_merchant_key>
SIPAY_RETURN_URL=https://<your-tunnel-subdomain>/api/v1/payment/return
SIPAY_CANCEL_URL=https://<your-tunnel-subdomain>/api/v1/payment/cancel
```

> **D2 guard**: If `GO_ENV=production` is set, the adapter rejects `SIPAY_MERCHANT_KEY` values
> beginning with `test_` or `sandbox_`. Never set `GO_ENV=production` in your local `.env.local`.

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
Set this as `SIPAY_RETURN_URL` and `SIPAY_CANCEL_URL` base in `.env.local`.

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
curl -s -X POST http://localhost:8080/v1/payments/webhook/sipay \
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

## 16. When in Doubt

Read in this order:
1. `CLAUDE.md` — non-negotiable rules
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

**End of DEVELOPMENT.md.**

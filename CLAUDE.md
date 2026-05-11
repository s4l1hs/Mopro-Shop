# CLAUDE.md — Mopro Shop Agent Constitution v7

> **READ THIS FIRST. NON-NEGOTIABLE.**
> This file overrides any conflicting instruction. If a user request violates these rules, STOP and ask for explicit override.
> All file paths assume project root is the repo root containing this file.

---

## 1. PROJECT IDENTITY

- **Project:** Mopro Shop — mobile-first marketplace where Mopro keeps the commission principal forever and refunds the annual interest income perpetually to the buyer as monthly Mopro Coin payments.
- **Architecture:** 3 Binary Hybrid Modular Monolith (NOT microservices).
- **Single VDS (launch):** 6 vCPU / 24 GB RAM / 120 GB disk. ~30 USD/month equivalent.
- **PRD reference:** v6.0 (Perpetual cashback from interest income + Category commission + 3-business-day payment delay).
- **Launch market:** Türkiye (TR). Default `MARKET=TR`, `DEFAULT_CURRENCY=TRY`, `DEFAULT_LOCALE=tr-TR`.
- **Coin issuance jurisdiction:** TBD — Dubai (VARA Cat 1 Issuer) or EU EMI (Lithuania / Estonia / Malta). NEVER Türkiye.
- **Future markets:** Architecture is global-ready. Adding a market = config + seed + translation file (zero code change).
- **Coin:** Mopro Coin, TL-pegged for TR launch (1 Coin ≈ 1 TL, narrow band 0.90–1.10 tolerated). Frozen monthly coin amount per plan; future TL devaluation does NOT change a buyer's monthly coin payment.
- **Business model (v6 PERPETUAL):** Category-based commission (42 categories at launch, range %5 to %20) + KDV. Mopro keeps the commission principal indefinitely on its balance sheet; the annual interest income from this principal (computed at a frozen reference rate of %50) is paid back to the buyer as 12 equal monthly Mopro Coin instalments **forever** (until plan cancellation/refund). Both the buyer cashback first instalment AND the seller net payout begin **delivered + 3 business days**.
- **Cashback formula (v6 LOCKED):** `monthly_coin = (price × commission_pct × reference_interest_rate) / 12` where `reference_interest_rate = 0.50` is the snapshotted constant per plan.
- **Mopro net economics:** Commission accumulates as Mopro's working capital forever (Mopro never repays principal). Interest is fully transferred to buyer as monthly coin. Mopro never loses principal; only spread risk if real interest drops below frozen reference rate (mitigated by adjusting reference rate for NEW plans).

---

## 2. ARCHITECTURE LOCK — IMMUTABLE

### 2.1 Three binaries ONLY

| Binary | Modules | Database | Network |
|---|---|---|---|
| `core-svc` | identity, catalog, cart, order, payment, seller, search | postgres-ecom | mopro-net |
| `fin-svc` | wallet, commission, treasury, **cashback-engine**, **seller-payout-engine** | postgres-ledger | mopro-fin-net (+ mopro-net for Redis) |
| `jobs-svc` | notification, support, media, sizefinder | postgres-ecom (own schemas) | mopro-net |

Adding a 4th binary requires explicit human approval and an ADR file under `/docs/adr/`.

### 2.2 FORBIDDEN

- DO NOT split modules into separate microservices (no `cart-svc`, `wallet-svc`, `cashback-svc`, `seller-payout-svc` binaries).
- DO NOT merge fin-svc into core-svc. fin-svc MUST stay a separate binary, separate DB, separate Docker network.
- DO NOT introduce new programming languages. Backend is Go 1.22+ only. Mobile is Flutter only.
- DO NOT replace PostgreSQL 16, Redis 7, Meilisearch v1.6, Caddy 2 without architecture review.
- DO NOT add Kubernetes, service mesh, or any other orchestrator. Docker Compose only at this stage.
- DO NOT introduce gRPC, Thrift, or other RPC frameworks without ADR.
- DO NOT hardcode `TRY`, `TRY_COIN`, `TR`, `tr-TR`, or any market-specific value in business code; always read from config or `ref_schema`.
- DO NOT hardcode commission percentages anywhere in code; ALWAYS read the snapshotted `commission_pct_bps` from `order_items` (set at order time from `ref_schema.commission_rules`).

### 2.3 Module layout — ENFORCED

```
/cmd/core-svc/main.go
/cmd/fin-svc/main.go
/cmd/jobs-svc/main.go
/cmd/migrate-tool/main.go
/cmd/mopro/main.go                # CLI for ops (cashback replay, payout retry, etc.)
/internal/identity/               → core-svc only
/internal/catalog/                → core-svc only (categories + commission_pct snapshot at sale)
/internal/cart/                   → core-svc only
/internal/order/                  → core-svc only (delivered_at + payout/cashback unlock_at)
/internal/payment/                → core-svc only (PSP adapter pattern)
/internal/seller/                 → core-svc only (seller panel transparency endpoints)
/internal/search/                 → core-svc only
/internal/wallet/                 → fin-svc only
/internal/commission/             → fin-svc only
/internal/treasury/               → fin-svc only (float yield + interest watch)
/internal/cashback/               → fin-svc only (cashback-engine: plan create + freeze + monthly cron)
/internal/sellerpayout/           → fin-svc only (seller-payout-engine: delivered+3 BD payout cron)
/internal/antifraud/              → core-svc only (v7: ML scoring decision module + review queue)
/internal/notification/           → jobs-svc only
/internal/support/                → jobs-svc only
/internal/media/                  → jobs-svc only
/internal/sizefinder/             → jobs-svc only
/internal/antifraud_inference/    → jobs-svc only (v7: serves ONNX models — NLP + vision)
/internal/einvoice/               → jobs-svc only (v7: GİB e-fatura/e-arşiv via Foriba)
/internal/eventbus/               → shared interface (Redis Streams impl)
/internal/outbox/                 → shared outbox publisher
/internal/ledger/                 → shared ledger types (fin-svc primary)
/pkg/logger/                      → slog wrapper, market-aware
/pkg/tracing/                     → OTel init
/pkg/crypto/                      → AES-GCM PII envelope
/pkg/currency/                    → ISO codes, Code type, validation, ref reader
/pkg/i18n/                        → translation key resolver
/pkg/httpx/                       → middleware (TraceAndLog, Idempotency, Locale)
/pkg/dbx/                         → pgx helpers, transaction patterns
/pkg/timex/                       → tz-aware helpers + AddBusinessDays(date, n, calendar)
```

---

## 3. COMMUNICATION RULES — IMMUTABLE

### 3.1 Within core-svc
- Modules communicate via **in-memory public interfaces only**.
- File: `/internal/<module>/api.go` exports `Service` interface.
- Other modules import the interface, NEVER the struct or repository directly.
- No HTTP, no gRPC inside core-svc. Plain Go function calls.

### 3.2 core-svc → fin-svc
- ONLY via Redis Streams events. No HTTP. No direct DB access.
- Event topic format: `<domain>.<entity>.<action>.v<n>` (e.g., `ecom.order.delivered.v1`).
- Every event MUST contain: `event_id`, `trace_id`, `span_id`, `occurred_at`, `idempotency_key`, `market`, `currency`, `payload`.
- The `ecom.order.delivered.v1` event is the trigger for BOTH cashback plan creation AND seller payout scheduling. Both consumers compute their `unlock_at` independently using `pkg/timex.AddBusinessDays(deliveredAt, 3, calendar="TR")`.

### 3.3 fin-svc → core-svc
- ONLY via Redis Streams events.

### 3.4 core-svc / fin-svc → jobs-svc
- HTTP for synchronous operations OR Redis Streams for async.
- jobs-svc NEVER writes to postgres-ledger.

### 3.5 Mobile/External → Backend
- Mobile clients reach Caddy via CloudFlare. Caddy routes by path prefix.
- Direct VDS IP access from outside is rejected (CloudFlare-only via host header validation).

---

## 4. FINANCIAL INVARIANTS — VIOLATING THESE BREAKS THE BUSINESS

### 4.1 Double-Entry Ledger
- Every financial transaction writes ≥ 2 ledger_entries rows.
- Within a transaction: `Sum(amount WHERE direction='D') == Sum(amount WHERE direction='C')`.
- Enforced by Postgres `DEFERRABLE INITIALLY DEFERRED` constraint trigger; do NOT bypass.

### 4.2 Multi-Currency Aware (CRITICAL)
- Every account has exactly ONE currency.
- All entries within a single transaction MUST share the same currency.
- Mixed-currency transactions are REJECTED at commit time by the trigger.
- Cross-currency moves (FX) happen as TWO transactions linked by a `fx_pair_id` reference: one in source currency, one in target currency. Treasury module is the ONLY consumer of FX accounts.

### 4.3 Append-Only
- `ledger_entries` and `transactions` NEVER UPDATE/DELETE.
- Postgres rules `no_update_ledger`, `no_delete_ledger` enforce this.
- Corrections happen ONLY through reversal transactions.

### 4.4 Idempotency-Key Mandatory
- Every write to `transactions` MUST have a unique `idempotency_key`.
- Every event consumer MUST check idempotency before applying.
- Every public POST/PUT endpoint MUST require an `Idempotency-Key` header.
- Cashback monthly cron uses `idempotency_key = "cashback:" + plan_id + ":" + YYYYMM`.
- Seller payout cron uses `idempotency_key = "payout:" + payout_id`.

### 4.5 Outbox Pattern Mandatory
- Code that produces a financial event MUST write the event to the `outbox` table within the SAME database transaction as the ledger write.
- A separate `outbox-publisher` worker XADDs from `outbox` to Redis Streams.
- Direct event publishing without outbox = CRITICAL BUG.

### 4.6 Money Type
- All amounts use integer minor units (`amount_minor BIGINT`); never float types.
- Every monetary value carries an explicit currency code.
- Initial launch market uses `currency='TRY'` for fiat and `currency='TRY_COIN'` for coin; this is the default but NOT hardcoded.
- Currency codes live in `ref_schema.currencies` (postgres-ecom). NEVER inline currency string literals in business logic; use the `pkg/currency.Code` type.

### 4.7 Cashback Engine Rules — v6 LOCKED PERPETUAL MODEL

The `cashback-engine` module inside fin-svc owns the cashback lifecycle. Hard rules:

- **Formula (deterministic, v6 PERPETUAL):**
  ```
  # Reference interest rate: 0.50 (snapshotted at plan creation, NEVER changes for an existing plan)
  ReferenceInterestRateBpsConst = 5000   // = %50.00, in basis points

  commission_minor   = round(price_minor * commission_pct_bps / 10000)
  yearly_yield_minor = round(commission_minor * reference_interest_rate_bps / 10000)
  monthly_coin_minor = round(yearly_yield_minor / 12)
  # No total_amount; no end date. Plan is PERPETUAL — payments forever until cancellation.
  ```
- **PERPETUAL is the v6 model.** There is no fixed termination date for a plan. Payments continue every month until the plan is cancelled (refund, account closure, admin action). Switching back to a fixed-term model requires a new constitution version + ADR.
- **Reference interest rate is FROZEN per plan at %50** (`ReferenceInterestRateBpsConst = 5000`). The snapshot lives in `cashback_schema.plans.reference_interest_rate_bps`. If the central bank rate moves, the rate for NEW plans MAY be adjusted (with CFO approval + ADR), but EXISTING plans keep their snapshot forever.
- **Plan generation is deterministic.** Given an `order_id`, `delivered_at`, snapshotted `commission_pct_bps` from `order_items`, and the reference interest rate active at order time, plan output (`monthly_amount_minor`, `start_date`) MUST be reproducible.
- **Plan is FROZEN at creation.** Once a plan is created, its `monthly_amount_minor`, `start_date`, `currency`, `reference_interest_rate_bps`, `delivered_at` NEVER change. A trigger `cashback_schema.plans_immutable` blocks UPDATE on these columns. Only `status` is mutable.
- **TL devaluation does NOT affect Mopro's coin payout.** Plan stores monthly coin amount, not TL amount. Mopro's TL-denominated obligation actually shrinks if TRY weakens.
- **First instalment unlock = `delivered_at + 3 business days`.** Computed via `pkg/timex.AddBusinessDays(deliveredAt, 3, ref_schema.business_calendars[market='TR'])`.
- **Monthly payment cron (`cashback-monthly-cron`) runs 1st of month 02:00 UTC.** For each `active` plan whose `start_date <= today`, the cron INSERTs a NEW `cashback_schema.payments` row with `period_yyyymm = current_period`, `amount_minor = plan.monthly_amount_minor`, then immediately posts the ledger move and marks status='paid'. Idempotent via UNIQUE `(plan_id, period_yyyymm)`.
- **Cashback is denominated in `TRY_COIN`** for TR launch; future markets use their own coin code (`EUR_COIN`, `USD_COIN`, etc.).
- **Cashback ledger move (per monthly payment):** `D equity:cashback_distribution:<COIN>` ← → `C liability:wallet:user_<id>:<COIN>`. Always single-currency per transaction. No pre-allocated total obligation in v6 (perpetual model — accrue as you go).
- **NO total obligation pre-allocation in v6.** Because the plan is perpetual, there is no finite total liability to provision upfront. Each month's payment is recognized in the period it is paid.
- **Cancellation:** If an order is cancelled or refunded BEFORE plan creation (within delivered+3BD), no plan is created, no coin minted. If cancelled AFTER plan creation, a reversal transaction reverses already-paid coin from user wallet (back to `equity:cashback_distribution`); future cron runs skip the cancelled plan; Mopro's commission principal is then released back to general retained earnings.
- **Partial refund AFTER plan creation:** `monthly_amount_minor` is reduced proportionally to the refunded fraction (this is an exception to plan immutability, allowed only via the official `mopro cashback partial-refund` CLI which atomically: (a) inserts an audit row in `plans_history`, (b) updates `monthly_amount_minor`); future months use the new amount; past months are NOT clawed back.

### 4.8 Seller Payout Engine Rules — v6 (unchanged from v5)

The `seller-payout-engine` module inside fin-svc owns seller net payout lifecycle. Hard rules:

- **Net amount calculation (deterministic):**
  ```
  gross_minor       = order_item.price_minor * quantity
  commission_minor  = round(gross_minor * commission_pct_bps / 10000)
  kdv_minor         = round(commission_minor * kdv_pct_bps / 10000)
  mopro_take_minor  = commission_minor + kdv_minor   # commission + KDV (KDV later remitted to state)
  seller_net_minor  = gross_minor - mopro_take_minor # cargo handled separately per § 2.3 of PRD
  ```
- **Payout schedule:** `unlock_at = delivered_at + 3 business days` (same business-day calendar as cashback).
- **Daily payout cron (`seller-payout-daily-cron`) runs every day 02:30 UTC.** Selects rows with `unlock_at <= today AND status='scheduled'`.
- **Each payout writes** `D liability:seller_payable:TRY` ← → `C asset:bank:escrow:TRY` and initiates a PSP transfer (idempotency-key = `payout_id`).
- **Plan is FROZEN at order completion (delivered_at).** Net amount is locked using the snapshotted commission and KDV at sale time.
- **Seller transparency endpoint:** `GET /api/v1/seller/orders/:id/breakdown` returns the exact breakdown (brüt, komisyon, KDV, hizmet bedeli=0, net) so the seller panel can render the Trendyol-style transparent table.

### 4.9 Float Yield Rules (Treasury)

- Treasury module manages the platform's float (commission revenue + 3-business-day delayed seller payout pool) in low-risk yield instruments.
- Yield is recognized monthly into `equity:retained_float_income:<currency>`.
- `treasury-monitor` cron tracks the central bank reference rate; if the rate drops > 5 percentage points below the v6 reference (%50) over 30 days, it raises a Slack alert recommending CFO to consider lowering `reference_interest_rate_bps` for NEW orders only (existing plans are FROZEN, never touched).
- The cron NEVER auto-changes the reference rate; CFO approval + ADR required. Only the rate for NEW plans changes; existing perpetual plans keep their snapshot forever.

---

## 5. DATABASE RULES — IMMUTABLE

- `postgres-ecom` and `postgres-ledger` are SEPARATE clusters with SEPARATE volumes, ports, passwords.
- fin-svc connects ONLY to `postgres-ledger` via `pgbouncer-ledger`.
- core-svc and jobs-svc connect ONLY to `postgres-ecom` via `pgbouncer-ecom`.
- Every module owns its own SCHEMA: `identity_schema`, `catalog_schema`, `wallet_schema`, `cashback_schema`, `commission_schema` (seller payouts here), etc.
- Cross-schema SQL `JOIN` is **FORBIDDEN**, with ONE exception: `ref_schema` (currencies, countries, locales, **categories**, **commission_rules**, **business_calendars**) is readable by every module.
- See `DATA_DICTIONARY.md` for full schema rules.

---

## 6. SECURITY RULES — IMMUTABLE

- All Postgres connections go through PgBouncer; never direct.
- Runtime container base MUST be `gcr.io/distroless/static-debian12:nonroot`.
- Containers MUST run with: `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]`, `read_only: true`.
- PII fields (`national_id`+`national_id_country`, phone, email, free-text user content, address fields) MUST be encrypted at rest with AES-GCM envelope encryption (`pkg/crypto.EncryptPII`).
- National ID format is country-specific; the field is generic with a companion ISO-3166 country code.
- Data protection compliance is the responsibility of the applicable jurisdiction's law (KVKK for Türkiye launch; GDPR for EU markets; PDPL for UAE if entered). Encryption mechanics are jurisdiction-agnostic.
- Secrets live in `/opt/mopro/.env` (chmod 600, root-only). NEVER commit secrets to Git.
- Step-up authentication (biometric/OTP) is required for: cashback-to-fiat conversion, withdrawal, account email/phone change, seller bank account modification.

---

## 7. RESOURCE LIMITS — DO NOT EXCEED

| Container | mem_limit | cpus | Notes |
|---|---|---|---|
| postgres-ecom | 5g | 2.0 | shm_size 256m |
| postgres-ledger | 3g | 1.5 | shm_size 128m |
| redis | 1.2g | 1.0 | maxmemory 800m + buffer |
| meilisearch | 1.5g | 1.0 | |
| caddy | 256m | 0.5 | |
| core-svc | 384m | 0.5 | go-defaults |
| fin-svc | 384m | 0.5 | go-defaults; cashback engine + seller-payout engine in-process |
| jobs-svc | 384m | 0.5 | go-defaults |

Reserve ≥ 11 GB for OS + Linux page cache. See `INFRASTRUCTURE.md`. NEVER raise mem_limit values to "use the headroom"; the headroom IS the design.

---

## 8. TECH STACK LOCK

| Layer | Tool | Version |
|---|---|---|
| Backend language | Go | 1.22+ |
| Mobile | Flutter | 3.x |
| Database | PostgreSQL | 16 |
| Cache + Streams | Redis | 7 |
| Search | Meilisearch | v1.6 |
| Reverse proxy | Caddy | 2 |
| CDN/WAF | CloudFlare | Free tier |
| Backup | Restic + Backblaze B2 | latest |
| Observability | Grafana Cloud Free + Grafana Agent | latest |
| CI | GitHub Actions | n/a |
| Image registry | ghcr.io | n/a |
| Orchestration | Docker Compose | latest |
| Localization | go-i18n + Flutter intl + easy_localization | latest |
| Payment (TR launch) | Sipay or Craftgate (adapter pattern) | n/a |
| Payment (EU, future) | Stripe Connect / Mollie / Adyen (adapter pattern) | n/a |
| Shipping (TR launch) | Aras / Yurtiçi / Sürat / MNG / HepsiJet / PTT (adapter pattern) | n/a |

Adding any new tool requires a written ADR in `/docs/adr/` with explicit human approval.

---

## 9. PSP ADAPTER PATTERN — MANDATORY

The platform integrates multiple payment providers across regions through a single interface.

```
/internal/payment/
├── api.go              # Service interface (provider-agnostic)
├── service.go          # orchestration
├── sipay/              # TR launch primary
├── craftgate/          # TR backup / marketplace lead
├── iyzico/             # TR alternative
├── stripe/             # EU launch (Phase 7+)
├── mollie/             # EU alternative
└── adyen/              # Enterprise EU + Global
```

Active provider is selected via env: `PSP_PROVIDER=sipay` (or `craftgate`, `stripe`, etc.).
Adding a NEW provider = new adapter folder + interface implementation + env value. The `payment.Service` contract NEVER changes.

Webhook handlers are provider-specific (each has its own signature verification) but normalize to a single internal `payment.Captured` event. Outbound seller payouts use the same provider's transfer API (e.g., Sipay marketplace transfer); the `sellerpayout.Service` contract is provider-agnostic.

---

## 10. AGENT BEHAVIOR

When given a task:

1. **READ** this file plus the relevant directive (`ARCHITECTURE.md`, `LEDGER_GUIDE.md`, `DATA_DICTIONARY.md`, etc.) before writing code.
2. **VERIFY** the task does not violate any rule above. If it does, STOP and report the conflict.
3. **WRITE** code that follows the patterns in `PROMPTS.md` for common workflows.
4. **TEST** new code with `go test -race ./...` and the specific module test suite.
5. **LINT** with `golangci-lint run` and `./scripts/check-module-boundaries.sh` before completing.
6. **NEVER** modify migration files that have already shipped to production.
7. **NEVER** introduce floating-point types for money. Always BIGINT minor units.
8. **NEVER** add new dependencies casually. If `go.mod` changes, justify in the PR description.
9. **NEVER** modify an existing cashback plan. Create a new plan or a reversal transaction instead.
10. **NEVER** modify a frozen seller payout. Reversal transaction only.
11. **NEVER** hardcode `TRY`, `TRY_COIN`, `TR`, market or locale strings in business code. Read from config/ref_schema.
12. **NEVER** hardcode commission percentages. Read from snapshot in `order_items.commission_pct_bps`.

---

## 11. VERIFICATION COMMANDS

Before finishing any task, run and report results:

```bash
# 1. Build all three binaries
go build -o /tmp/core-svc ./cmd/core-svc
go build -o /tmp/fin-svc  ./cmd/fin-svc
go build -o /tmp/jobs-svc ./cmd/jobs-svc

# 2. Run all tests (race detector on)
go test -race ./...

# 3. Run linter (boundary checks)
golangci-lint run

# 4. Verify no forbidden patterns
./scripts/check-module-boundaries.sh

# 5. Verify cashback + payout engine invariants (property tests)
go test -tags=integration -run Property ./internal/cashback/...
go test -tags=integration -run Property ./internal/sellerpayout/...
go test -tags=integration -run Property ./internal/wallet/...
```

If any of these fail, the task is NOT complete. Do not commit, do not push.

---

## 12. ESCALATION

When in doubt, refuse and ask. The cost of asking a question is low; the cost of breaking the ledger, the cashback engine, the seller payout engine, or violating module boundaries is catastrophic.

If you encounter a request that would:
- Modify an existing cashback plan or seller payout
- Bypass the multi-currency aware trigger
- Change the perpetual model to a fixed-term model (in v6 model)
- Change `reference_interest_rate_bps` from 5000 for an EXISTING plan (frozen)
- Change the 3-business-day delay
- Hardcode a market/currency/locale/commission percentage
- Add a new microservice binary
- Skip the outbox pattern
- Use float for money
- Cross-import between modules without going through the public Service interface

…STOP, quote the rule above, and ask the human owner.

---

**End of CLAUDE.md.** This file is the constitution. ARCHITECTURE.md, DATA_DICTIONARY.md, LEDGER_GUIDE.md, INFRASTRUCTURE.md, DISASTER_RECOVERY.md, DEVELOPMENT.md, PROMPTS.md elaborate on it. They MUST NOT contradict it.

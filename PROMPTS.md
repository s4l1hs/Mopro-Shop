# PROMPTS.md — Master Prompt Library v7

This file is the official anthology of commands an operator gives to Claude Code (or any autonomous coding agent) to build Mopro Shop from an empty repository to a launched production system. Every prompt is copy-paste-ready, restrictive, and faithful to PRD v6.0.

## How to Use

1. Pick the phase you are in (0 through 7).
2. Find the matching prompt by goal.
3. Copy the **Copy-Paste Prompt** block verbatim and feed it to the agent.
4. After the agent completes, run the **Verification / Done Criteria** checklist. Do not advance to the next prompt until every item passes.

## Conventions

- Every prompt opens with `READ FIRST: CLAUDE.md, ARCHITECTURE.md, DATA_DICTIONARY.md, LEDGER_GUIDE.md, INFRASTRUCTURE.md.`
- `ghcr.io/mopro/<binary>` is the canonical image namespace.
- Module path: `github.com/mopro/platform`.
- Backend: Go 1.22+. Mobile: Flutter 3.x. DB: PostgreSQL 16. Cache: Redis 7.
- Single VDS: 6 vCPU / 24 GB RAM / 120 GB disk.
- Launch market: `MARKET=TR`, `DEFAULT_CURRENCY=TRY`, `DEFAULT_LOCALE=tr-TR`.
- **Cashback v6 LOCKED model (PERPETUAL):** monthly = (price × commission_pct_bps × ref_rate_bps / 10000 / 10000) / 12, perpetual; ref_rate_bps frozen at 5000 (%50) per plan.
- **Seller payout v5 LOCKED model:** unlock = delivered_at + 3 business days (read TR business calendar).
- Both plan and seller payout are FROZEN at creation; only `status` mutable.

---

# PHASE 0 — Infrastructure & Skeleton

## Prompt 0.1 — Initialize Monorepo Skeleton

**Phase & Goal:** Phase 0. Create repo layout, Go modules, linter rules, Makefile, base config so `make verify` runs on an empty project.

**Copy-Paste Prompt:**

```
READ FIRST: CLAUDE.md, ARCHITECTURE.md, DATA_DICTIONARY.md, INFRASTRUCTURE.md, DEVELOPMENT.md.

Create the initial monorepo skeleton for Mopro Shop. Do not write business logic; only create the structure, config, and stubs that compile.

CREATE THESE PATHS (exact list):

/cmd/core-svc/main.go
/cmd/fin-svc/main.go
/cmd/jobs-svc/main.go
/cmd/migrate-tool/main.go
/cmd/mopro/main.go

/internal/identity/
/internal/catalog/
/internal/cart/
/internal/order/
/internal/payment/
/internal/seller/
/internal/search/
/internal/wallet/
/internal/commission/
/internal/treasury/
/internal/cashback/         ← cashback-engine module (fin-svc)
/internal/sellerpayout/     ← NEW v5: seller-payout-engine module (fin-svc)
/internal/notification/
/internal/support/
/internal/media/
/internal/sizefinder/
/internal/eventbus/
/internal/outbox/
/internal/ledger/

/pkg/logger/
/pkg/tracing/
/pkg/crypto/
/pkg/currency/              ← ISO codes, Code type, ref reader
/pkg/i18n/                  ← translation key resolver
/pkg/httpx/
/pkg/dbx/
/pkg/timex/                 ← MUST include AddBusinessDays(date, n, calendar) helper

/migrations/ecom/
/migrations/ecom/seed/
/migrations/ledger/

/build/Dockerfile
/.dockerignore

/deploy/docker-compose.yml
/deploy/caddy/Caddyfile
/deploy/postgres-ecom/postgresql.conf
/deploy/postgres-ledger/postgresql.conf
/deploy/redis/redis.conf
/deploy/grafana-agent/agent.yaml
/deploy/pgbouncer/pgbouncer-ecom.ini
/deploy/pgbouncer/pgbouncer-ledger.ini

/scripts/install-hooks.sh
/scripts/check-module-boundaries.sh
/scripts/new-module.sh
/scripts/disk-watch.sh
/scripts/disk-hygiene.sh
/scripts/ledger-reconcile.sh
/scripts/restore-drill.sh
/scripts/backup.sh
/scripts/cashback-monthly-cron.sh
/scripts/seller-payout-daily-cron.sh    ← NEW v5

/.golangci.yml
/.gitignore
/.editorconfig
/Makefile
/go.mod
/.env.example
/README.md

For each /internal/<name>/ directory, create five empty Go files:
  api.go (package <name>; declares 'type Service interface{}' and 'type Repository interface{}')
  service.go
  repository.go
  domain.go
  errors.go

For each /cmd/<binary>/main.go: minimal `func main(){}` that loads env via os.Getenv("SVC_NAME"), prints "starting <binary> market=$MARKET", exits 0.

Module path: github.com/mopro/platform

go.mod requirements:
  - go 1.22
  - github.com/jackc/pgx/v5 (latest)
  - github.com/redis/go-redis/v9 (latest)
  - github.com/golang-migrate/migrate/v4 (latest)
  - github.com/leanovate/gopter (latest)
  - go.opentelemetry.io/otel (latest)
  - go.opentelemetry.io/otel/sdk (latest)

.golangci.yml: depguard rules from DEVELOPMENT.md § 9 verbatim (includes new cashback + sellerpayout rules).

Makefile targets: verify, fmt, vet, test, lint, boundaries, property-cashback, property-payout, property-ledger, build-core, build-fin, build-jobs, build-migrate, build-mopro, run-local, down-local. The verify target chains all check sub-targets.

scripts/check-module-boundaries.sh: body from DEVELOPMENT.md § 10 verbatim (includes cashback plan UPDATE block, seller_payouts core fields immutability check, and PaybackMonths=24 enforcement).

scripts/install-hooks.sh: installs pre-push hook running `make verify`.

.gitignore: .env*, !.env.example, /data/, /tmp/, /vendor/, *.test, coverage.out, .DS_Store, .idea/, .vscode/.

.dockerignore: .git/, .github/, *.md, docs/, deploy/, test/, testdata/, **/*.test, coverage.out, node_modules/, .local/.

.env.example: every variable from DEVELOPMENT.md § 3 with placeholder values like "REPLACE_ME". Never commit real secrets.

After creating the skeleton:
  1. Run `go mod tidy`.
  2. Run `make verify`. MUST pass on empty skeleton.
  3. Run `go build ./...`. MUST succeed.

DO NOT add business logic. DO NOT introduce new dependencies. DO NOT add HTTP frameworks yet (Phase 1 chooses).

Report at end: list of files created, output of `make verify`, output of `go build ./...`.
```

**Verification / Done Criteria:**
- [ ] All listed paths exist exactly as specified.
- [ ] `go mod tidy` produces no errors.
- [ ] `go build ./...` succeeds.
- [ ] `make verify` exits 0 with all sub-targets green.
- [ ] `golangci-lint run` exits 0.
- [ ] `git status` shows only intended files.
- [ ] `scripts/check-module-boundaries.sh` exits 0.

---

## Prompt 0.2 — Create postgres-ecom Init Scripts (with v5 ref_schema seeds)

**Phase & Goal:** Phase 0. Provision postgres-ecom with module schemas + ref_schema (currencies, countries, locales, categories, **commission_rules** with 42 categories, **business_calendars** with TR holidays).

**Copy-Paste Prompt:**

```
READ FIRST: DATA_DICTIONARY.md (especially § 2 and § 5), CLAUDE.md § 5.

Create Postgres init scripts for postgres-ecom. Run automatically when container starts on empty volume.

PATHS TO CREATE:

/deploy/postgres-ecom/init/00-extensions.sql
/deploy/postgres-ecom/init/10-roles.sql
/deploy/postgres-ecom/init/20-schemas.sql
/deploy/postgres-ecom/init/30-grants.sql
/deploy/postgres-ecom/init/40-ref-schema.sql        ← currencies, countries, locales, categories, commission_rules, business_calendars
/deploy/postgres-ecom/init/50-ref-seed.sql          ← seed all 42 commission rules + TR business calendar 2026-2030
/deploy/postgres-ecom/init/99-set-passwords.sh

CONTENT:

00-extensions.sql:
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
  CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

10-roles.sql:
  CREATE LOGIN ROLE per module: identity_user, catalog_user, cart_user, order_user,
    payment_user, seller_user, search_user, notification_user, support_user, media_user, sizefinder_user.
  All NOSUPERUSER, NOCREATEDB, NOCREATEROLE, INHERIT, LOGIN.
  Placeholder password 'REPLACE_BY_INIT'; real passwords set by 99-set-passwords.sh from env.

20-schemas.sql:
  REVOKE ALL ON SCHEMA public FROM PUBLIC;
  CREATE SCHEMA <module>_schema AUTHORIZATION <module>_user; (× 11)

30-grants.sql:
  Per module: GRANT USAGE ON SCHEMA <module>_schema; GRANT SELECT/INSERT/UPDATE/DELETE on tables.
  Plus GRANT SELECT on ALL TABLES IN SCHEMA ref_schema to PUBLIC.

40-ref-schema.sql:
  Create ref_schema with tables:
    - currencies(code TEXT PRIMARY KEY, kind TEXT, minor_unit_scale INT, symbol TEXT, name_en TEXT, active BOOL)
    - countries(code TEXT PRIMARY KEY, name_en TEXT, default_currency TEXT, default_locale TEXT, default_timezone TEXT)
    - locales(tag TEXT PRIMARY KEY, name_en TEXT, active BOOL)
    - categories(id BIGINT PRIMARY KEY, slug TEXT UNIQUE, name_tr TEXT, name_en TEXT, parent_id BIGINT, active BOOL)
    - commission_rules(id BIGSERIAL PRIMARY KEY, market TEXT, category_id BIGINT REFERENCES categories(id),
        commission_pct_bps INT NOT NULL CHECK (commission_pct_bps BETWEEN 0 AND 10000),
        kdv_pct_bps INT NOT NULL,
        effective_from TIMESTAMPTZ DEFAULT now(), effective_to TIMESTAMPTZ, active BOOL DEFAULT TRUE,
        UNIQUE(market, category_id, effective_from))
    - business_calendars(market TEXT, date DATE, reason TEXT, PRIMARY KEY(market, date))

50-ref-seed.sql:
  Seed exact rows from DATA_DICTIONARY.md § 2.5 verbatim:
    - 8 currency rows (TRY/TRY_COIN active; others inactive)
    - 4 country rows (TR active; others ready)
    - 4 locale rows (tr-TR active; others ready)
    - 42 category rows with their slugs + Turkish + English names
    - 42 commission_rules rows for market='TR' with the exact bps values from PRD v5 Section 2.2.2
      (Atkı/Bere=2000, Saat=2000, ..., Akıllı Telefon=700, ..., Çiçek=2000)
    - business_calendars: all official Turkish public holidays for 2026-2030 (Yılbaşı, Ulusal Egemenlik,
      Emek Günü, Atatürk'ü Anma, Demokrasi Günü, Zafer Bayramı, Cumhuriyet Bayramı, plus floating
      Ramazan/Kurban dates per Diyanet).

99-set-passwords.sh:
  Reads ECOM_DB_PASSWORD, IDENTITY_DB_PASSWORD, etc. from env and runs ALTER USER per role.

After applying:
  Verify with:
    SELECT count(*) FROM ref_schema.commission_rules WHERE market='TR' AND active=TRUE;  -- expect 42
    SELECT count(*) FROM ref_schema.business_calendars WHERE market='TR';  -- expect ~50

Report: SQL snippets, init log output, verification query results.
```

**Verification / Done Criteria:**
- [ ] `docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c "\dn"` lists all 11 module schemas + ref_schema.
- [ ] `SELECT count(*) FROM ref_schema.commission_rules WHERE market='TR'` returns 42.
- [ ] `SELECT commission_pct_bps FROM ref_schema.commission_rules WHERE category_id=30` (Akıllı Telefon) returns 700.
- [ ] `SELECT count(*) FROM ref_schema.business_calendars WHERE market='TR'` returns 50+.
- [ ] No errors in init logs.
- [ ] `make verify` still passes.

---

## Prompt 0.3 — Create postgres-ledger with Multi-Currency D=C Trigger + Cashback + Seller Payout Schemas

**Phase & Goal:** Phase 0. Provision postgres-ledger with wallet/commission/treasury/cashback schemas. Install the multi-currency-aware D=C trigger. Add the cashback plan immutability trigger AND the seller payout immutability trigger.

**Copy-Paste Prompt:**

```
READ FIRST: DATA_DICTIONARY.md § 8, § 9, LEDGER_GUIDE.md § 3, § 4, § 7, § 8.

Create Postgres init scripts for postgres-ledger.

PATHS TO CREATE:

/deploy/postgres-ledger/init/00-extensions.sql
/deploy/postgres-ledger/init/10-roles.sql
/deploy/postgres-ledger/init/20-schemas.sql
/deploy/postgres-ledger/init/30-grants.sql
/deploy/postgres-ledger/init/40-wallet-schema.sql
/deploy/postgres-ledger/init/41-trigger-d-equals-c.sql       ← multi-currency aware
/deploy/postgres-ledger/init/42-rules-no-update-delete.sql
/deploy/postgres-ledger/init/50-cashback-schema.sql          ← v5: total_months CHECK = 24
/deploy/postgres-ledger/init/51-cashback-immutable-trigger.sql
/deploy/postgres-ledger/init/60-seller-payout-schema.sql     ← NEW v5
/deploy/postgres-ledger/init/61-seller-payout-immutable-trigger.sql  ← NEW v5
/deploy/postgres-ledger/init/70-chart-of-accounts-seed.sql   ← v5: includes retained_commission, seller_payable, retained_commission
/deploy/postgres-ledger/init/99-set-passwords.sh

00-extensions.sql, 10-roles.sql (wallet_user, commission_user, treasury_user, cashback_user, sellerpayout_user),
20-schemas.sql, 30-grants.sql: same pattern as postgres-ecom.

40-wallet-schema.sql:
  CREATE TABLE wallet_schema.accounts (id, type, owner_type, owner_id, currency NOT NULL, status, created_at)
  CREATE TABLE wallet_schema.transactions (id, type, reference, fx_pair_id, idempotency_key UNIQUE, status, created_at)
  CREATE TABLE wallet_schema.ledger_entries (id, transaction_id FK, account_id FK, direction CHAR(1) CHECK IN ('D','C'), amount_minor BIGINT > 0, created_at)
  CREATE TABLE wallet_schema.outbox (id, aggregate, event_type, payload JSONB, idempotency_key UNIQUE, trace_id, span_id, market, currency, published_at, created_at)
  CREATE MATERIALIZED VIEW wallet_schema.balances ...

41-trigger-d-equals-c.sql:
  Function wallet_schema.enforce_double_entry() per LEDGER_GUIDE.md § 4 verbatim:
    - First check: array_agg(DISTINCT a.currency) for the txn → must be size 1.
    - Second check: SUM(D) == SUM(C) within the txn.
  CREATE CONSTRAINT TRIGGER ledger_balance_check
    AFTER INSERT ON wallet_schema.ledger_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION wallet_schema.enforce_double_entry();

42-rules-no-update-delete.sql:
  CREATE RULE no_update_ledger ... DO INSTEAD NOTHING (× 4: ledger_entries × {UPDATE,DELETE}, transactions × {UPDATE,DELETE}).

50-cashback-schema.sql (v6 PERPETUAL — no rules table, no total fields):
  CREATE TABLE cashback_schema.plans:
    - id BIGSERIAL PRIMARY KEY
    - order_id BIGINT NOT NULL
    - user_id BIGINT NOT NULL
    - monthly_amount_minor BIGINT NOT NULL CHECK > 0                        ← v6: aylık coin (sabit, dondurulmuş)
    - currency TEXT NOT NULL DEFAULT 'TRY_COIN'
    - reference_interest_rate_bps INTEGER NOT NULL DEFAULT 5000             ← v6: %50 = 5000 bps (snapshot)
    - start_date DATE NOT NULL                                              ← = delivered + 3 BD
    - status TEXT NOT NULL DEFAULT 'active' CHECK IN ('active','cancelled','suspended')
    - delivered_at TIMESTAMPTZ NOT NULL
    - market TEXT NOT NULL DEFAULT 'TR'
    - commission_snapshot JSONB NOT NULL                                    ← per-item commission breakdown (audit)
    - idempotency_key TEXT NOT NULL UNIQUE
    - created_at, updated_at TIMESTAMPTZ
    -- v6 NOTES: NO total_amount_minor, NO total_months, NO end_date — plan is PERPETUAL.

  CREATE TABLE cashback_schema.plans_history (
    id BIGSERIAL PK, plan_id FK, field_changed TEXT, old_value TEXT, new_value TEXT,
    reason TEXT, changed_by TEXT, created_at TIMESTAMPTZ
  )  -- audit trail for partial-refund monthly_amount changes (only allowed mutation path)

  CREATE TABLE cashback_schema.payments (id, plan_id FK, period_yyyymm INTEGER CHECK BETWEEN 202600 AND 209912,
    scheduled_date, paid_date, amount_minor > 0, status, ledger_transaction_id,
    idempotency_key UNIQUE, attempt_count, last_attempt_at, last_error, created_at)
    -- v6: no pre-seed; cron INSERTs one row per active plan per month.
  CREATE UNIQUE INDEX cashback_payments_plan_period_uq ON cashback_schema.payments(plan_id, period_yyyymm);
  CREATE INDEX cashback_plans_active_due_idx ON cashback_schema.plans(start_date) WHERE status='active';

51-cashback-immutable-trigger.sql:
  Function cashback_schema.enforce_plan_immutable() per DATA_DICTIONARY.md § 8 verbatim.
  TRIGGER BEFORE UPDATE ON cashback_schema.plans.
  Allows monthly_amount_minor change ONLY when accompanied by a plans_history row created in the
  same transaction (within the last 2 seconds).

60-seller-payout-schema.sql (NEW v5):
  CREATE TABLE commission_schema.seller_payouts:
    - id BIGSERIAL PRIMARY KEY
    - order_id BIGINT NOT NULL
    - seller_id BIGINT NOT NULL
    - amount_minor BIGINT NOT NULL CHECK > 0
    - currency TEXT NOT NULL DEFAULT 'TRY'
    - delivered_at TIMESTAMPTZ NOT NULL
    - unlock_at DATE NOT NULL                                  ← = delivered + 3 BD
    - paid_at TIMESTAMPTZ
    - psp_transfer_id TEXT
    - status TEXT NOT NULL DEFAULT 'scheduled' CHECK IN ('scheduled','processing','paid','failed','cancelled','reversed')
    - market TEXT NOT NULL DEFAULT 'TR'
    - ledger_transaction_id BIGINT
    - idempotency_key TEXT NOT NULL UNIQUE
    - attempt_count INTEGER NOT NULL DEFAULT 0
    - last_attempt_at TIMESTAMPTZ
    - last_error TEXT
    - created_at, updated_at TIMESTAMPTZ
  CREATE INDEX seller_payouts_due_idx ON commission_schema.seller_payouts(unlock_at, status) WHERE status='scheduled';
  CREATE INDEX seller_payouts_seller_idx ON commission_schema.seller_payouts(seller_id, created_at DESC);

61-seller-payout-immutable-trigger.sql:
  Function commission_schema.enforce_payout_immutable() per DATA_DICTIONARY.md § 9 verbatim.
  TRIGGER BEFORE UPDATE ON commission_schema.seller_payouts.

70-chart-of-accounts-seed.sql (v6 PERPETUAL):
  Insert one account per pattern from LEDGER_GUIDE.md § 2:
    asset:bank:escrow:TRY
    asset:bank:outbound_pending:TRY
    liability:bank_outbound:TRY
    liability:seller_payable:TRY
    equity:cashback_distribution:TRY_COIN          ← v6: monthly coin distribution counter-equity
    equity:retained_commission:TRY                 ← v6: Mopro's permanent capital (commission accumulates here)
    equity:retained_float_income:TRY               ← 3BD float yield
    equity:fx_gain_loss:TRY
    liability:kdv_payable:TRY
  All status='active'. owner_type='platform'. NO user wallet accounts here (created lazily by wallet.OpenOrFindUserWallet).

99-set-passwords.sh: same pattern.

Run init. Verify by inserting a synthetic transaction with mixed currencies → MUST fail. Insert a balanced single-currency transaction → MUST succeed.

Report SQL output, trigger validation results.
```

**Verification / Done Criteria:**
- [ ] All schemas + tables exist.
- [ ] `INSERT` of mixed-currency transaction is REJECTED with the specific exception.
- [ ] `INSERT` of D-only or C-only is REJECTED at COMMIT.
- [ ] `UPDATE cashback_schema.plans SET total_amount_minor=...` raises plan immutability exception.
- [ ] `UPDATE commission_schema.seller_payouts SET amount_minor=...` raises payout immutability exception.
- [ ] `INSERT INTO cashback_schema.plans (... total_months=12 ...)` violates CHECK constraint (must be 24).
- [ ] Chart of accounts has all v5 accounts seeded.

---

## Prompt 0.4 — Implement EventBus + Outbox Publisher (market+currency aware)

**Phase & Goal:** Phase 0. Implement Redis Streams event bus interface + outbox publisher worker. Both must propagate `market` and `currency` labels through every event.

**Copy-Paste Prompt:**

```
READ FIRST: ARCHITECTURE.md § 5, LEDGER_GUIDE.md § 5, CLAUDE.md § 3.

Implement /internal/eventbus/ + /internal/outbox/.

/internal/eventbus/api.go:
  type Event struct {
    EventID, EventType, Aggregate, IdempotencyKey string
    Market, Currency  string                  // mandatory labels
    TraceID, SpanID   string
    OccurredAt        time.Time
    Payload           json.RawMessage
  }
  type Publisher interface { Publish(ctx, Event) error }
  type Consumer  interface { Subscribe(ctx, group, topic string, handler func(Event) error) error }

/internal/eventbus/redis_bus.go:
  Implement Publisher with redis.XAdd; serialize fields explicitly so Market and Currency live in the stream entry.
  Implement Consumer with XREADGROUP + XACK; per-event handler runs in its own goroutine bounded by a worker pool of 8.

/internal/outbox/api.go:
  type Row struct { ID, Aggregate, EventType, IdempotencyKey, Market, Currency, TraceID, SpanID; Payload json.RawMessage }
  type Repository interface { Insert(ctx, tx, Row) error; FetchUnpublished(ctx, limit) ([]Row, error); MarkPublished(ctx, id) error }

/internal/outbox/publisher.go:
  Worker that loops:
    SELECT * FROM outbox WHERE published_at IS NULL FOR UPDATE SKIP LOCKED LIMIT 100
    For each row: bus.Publish(...) with Market and Currency from the row.
    UPDATE outbox SET published_at = now() WHERE id = ?
  Implements graceful shutdown; uses context cancellation; emits metric mopro_<svc>_outbox_publish_total{market,currency,event_type,result}.

/internal/outbox/repository.go:
  Implement against pgx using the pattern from LEDGER_GUIDE.md § 5.

Tests:
  - Property test: ANY successful Insert is eventually Published in the order it was inserted (per aggregate).
  - Idempotency: re-publishing a row with same idempotency_key results in zero duplicate downstream side-effects (test consumer counts).

Report: file list, test output, sample log lines showing trace_id propagation.
```

**Verification / Done Criteria:**
- [ ] `Insert` writes to outbox; `FetchUnpublished` returns it.
- [ ] Publisher drains outbox to Redis Streams; consumer receives event with all fields including Market and Currency.
- [ ] Property test passes 1000 iterations.
- [ ] Idempotency dedup verified.

---

## Prompt 0.5 — Bootstrap Docker Compose Stack

**Phase & Goal:** Phase 0. Bring up the entire 9-container stack with resource limits enforced.

**Copy-Paste Prompt:**

```
READ FIRST: INFRASTRUCTURE.md § 2-7, ARCHITECTURE.md § 2.

Create /deploy/docker-compose.yml that runs:
  caddy, postgres-ecom, postgres-ledger, pgbouncer-ecom, pgbouncer-ledger, redis, meilisearch, grafana-agent
  + core-svc, fin-svc, jobs-svc

Apply x-go-defaults anchor from INFRASTRUCTURE.md § 5 to all 3 Go binaries.
Apply Postgres exception from § 5.2 to both Postgres containers.

Networks:
  mopro-net 172.30.0.0/24 (all except postgres-ledger and pgbouncer-ledger)
  mopro-fin-net 172.31.0.0/24 (postgres-ledger, pgbouncer-ledger, fin-svc)

Mounts:
  /opt/mopro/data/postgres-ecom → postgres-ecom:/var/lib/postgresql/data
  /opt/mopro/data/postgres-ledger → postgres-ledger:/var/lib/postgresql/data
  /opt/mopro/data/redis → redis:/data
  /opt/mopro/data/meili → meilisearch:/meili_data
  Init scripts mounted into /docker-entrypoint-initdb.d/ for both Postgres containers.

Environment files: ${ROOT}/.env (chmod 600 root-only).

Healthchecks per service.
Restart policy: unless-stopped on all.

After compose up:
  docker compose ps  → all healthy
  docker exec core-svc nc -zv postgres-ledger 5432   → MUST FAIL
  docker exec fin-svc  nc -zv postgres-ledger 5432   → MUST SUCCEED
  docker exec fin-svc  nc -zv redis 6379             → MUST SUCCEED
  docker stats --no-stream  → no container exceeds its mem_limit
  curl -sf http://localhost/healthz  → 200

Report: compose file, healthcheck output, stats snapshot.
```

**Verification / Done Criteria:**
- [ ] All 9 containers healthy.
- [ ] Network isolation verified (3 nc commands).
- [ ] Memory totals match the 12.6 GB target (+/- 5%).

---

## Prompt 0.6 — Caddy Reverse Proxy with Base Routes

**Phase & Goal:** Phase 0. Configure Caddy with TLS, rate limiting, and the four route groups.

**Copy-Paste Prompt:**

```
READ FIRST: ARCHITECTURE.md § 1.

Create /deploy/caddy/Caddyfile:
  api.moproshop.com:
    reverse_proxy core-svc:8080
    handle_path /v1/wallet/*  { reverse_proxy fin-svc:8080 }
    handle_path /v1/cashback/* { reverse_proxy fin-svc:8080 }
    handle_path /v1/payouts/*  { reverse_proxy fin-svc:8080 }
    handle_path /v1/jobs/*     { reverse_proxy jobs-svc:8080 }
    rate_limit { zone api_per_ip { key {client_ip} window 1m max 600 } }
    @cf_only header CF-Connecting-IP * { request_header X-Forwarded-For {http.request.header.CF-Connecting-IP} }
    not @cf_only respond 403

  seller.moproshop.com:
    reverse_proxy core-svc:8080  (only /api/v1/seller/* + static seller panel)

  img.moproshop.com:
    reverse_proxy https://<b2-bucket-public-url>

  TLS: managed automatically (Let's Encrypt) for HTTPS; in dev use internal CA.

After deploying: curl -sk https://api.moproshop.com/healthz returns 200 from core-svc.

Report Caddyfile + curl outputs.
```

**Verification / Done Criteria:**
- [ ] HTTPS works (or dev CA mode).
- [ ] Routes reach the correct binary.
- [ ] Rate limit kicks in at 601 requests/min from same IP.

---

# PHASE 1 — E-Commerce Core

## Prompt 1.1 — Create catalog Module (Multi-Currency, Multi-Language, Category-Aware)

**Phase & Goal:** Phase 1. Catalog module with products + variants + translations + category-driven commission preview.

**Copy-Paste Prompt:**

```
READ FIRST: DATA_DICTIONARY.md § 6, CLAUDE.md § 2-3.

Implement /internal/catalog/ inside core-svc.

Domain types in /internal/catalog/domain.go:
  Product { ID, SellerID, CategoryID, Brand, DefaultCurrency, DefaultLocale, Status, ... }
  Variant { ID, ProductID, SKU, Color, Size, PriceMinor, PriceCurrency, Stock, ImageKeys }
  ProductTranslation { ProductID, Locale, Title, Description }
  CategoryCommission { CategoryID, CommissionPctBps, KdvPctBps }   ← read from ref_schema

Service interface in /internal/catalog/api.go:
  CreateProduct(ctx, req) (Product, error)
  AddVariant(ctx, productID, req) (Variant, error)
  UpdateTranslation(ctx, productID, locale, title, description) error
  GetByID(ctx, id) (Product, []Variant, []ProductTranslation, error)
  Search(ctx, query, locale, market) ([]Product, error)
  GetCommissionForCategory(ctx, market, categoryID) (CategoryCommission, error)   ← reads ref_schema.commission_rules

Repository implements all SQL queries. Use pgx.
Migration /migrations/ecom/0010_catalog.sql per DATA_DICTIONARY.md § 6.
Validate: variant.PriceCurrency MUST exist in ref_schema.currencies (active=TRUE).

HTTP handlers in core-svc:
  POST /v1/products
  POST /v1/products/:id/variants
  PUT  /v1/products/:id/translations/:locale
  GET  /v1/products/:id
  GET  /v1/categories/:id/commission?market=TR    ← used by seller panel cashback preview

For each handler: Idempotency-Key required, Locale resolved from Accept-Language.

Add 80%+ unit tests. Add integration test that creates a product with TRY pricing + Turkish translation + queries it back.

Report: file list, test output, sample API curls.
```

**Verification / Done Criteria:**
- [ ] All endpoints work.
- [ ] `GET /v1/categories/30/commission?market=TR` returns `{commission_pct_bps: 700, kdv_pct_bps: 2000}`.
- [ ] Coverage ≥ 80%.

---

## Prompt 1.2 — Create cart Module + Redis Lua Stock Reservation

**Phase & Goal:** Phase 1. Cart with Redis-backed stock reservation (atomic) using a single Lua script.

**Copy-Paste Prompt:**

```
READ FIRST: ARCHITECTURE.md § 5 (the in-memory module communication rule), CLAUDE.md § 3.

Implement /internal/cart/ inside core-svc.

Service:
  AddItem(ctx, userID, variantID, qty) error
  RemoveItem(ctx, userID, variantID) error
  GetCart(ctx, userID) (Cart, error)
  Reserve(ctx, userID) (reservationID string, error)   ← used at checkout
  Release(ctx, reservationID) error                    ← saga compensation

State: Redis hash per cart (mopro:cart:user_<id>).
Stock reservation: Redis Lua script that, atomically:
  1. Reads current variant stock.
  2. If stock >= qty: DECRBY stock; PUT reservation with TTL 15 min.
  3. Else: returns OUT_OF_STOCK.

Cross-module call: cart calls catalog.GetVariant via in-memory function call (NOT HTTP, NOT direct repo).
The cart module has NO direct access to catalog repository.

Add property test: 100 concurrent reserve attempts on a stock=10 variant succeed at most 10 times.

Report: file list, test output, Lua script.
```

**Verification / Done Criteria:**
- [ ] Property test passes; never overshoots stock.
- [ ] depguard rejects an import of internal/catalog/repository from cart.

---

## Prompt 1.3 — Create order Module + ecom.order.delivered.v1 Event Emission

**Phase & Goal:** Phase 1. Order saga (pending_payment → paid → shipped → delivered → cancelled/refunded). On delivered, emit `ecom.order.delivered.v1` carrying the snapshotted commission/KDV per item — this triggers BOTH cashback engine and seller-payout engine in fin-svc.

**Copy-Paste Prompt:**

```
READ FIRST: DATA_DICTIONARY.md § 7, LEDGER_GUIDE.md § 7.1, ARCHITECTURE.md § 5.

Implement /internal/order/ inside core-svc.

Domain:
  Order { ID, UserID, Status, SubtotalMinor, ShippingMinor, ShippingPayer, TotalMinor, Currency,
          Market, DeliveredAt, CashbackEligible, CashbackCurrency, IdempotencyKey, ... }
  OrderItem { ID, OrderID, VariantID, SellerID, CategoryID, Qty,
              UnitPriceMinor, UnitPriceCurrency,
              CommissionPctBps,             ← snapshot from ref_schema.commission_rules at order time
              KdvPctBps,                    ← snapshot
              CommissionAmountMinor,        ← computed = unit*qty*pct/10000
              KdvAmountMinor,               ← computed
              SellerNetMinor                ← computed = unit*qty - commission - kdv
            }

Service:
  Checkout(ctx, userID, cartID, addressID, paymentRef, idempotencyKey) (Order, error)
    1. Acquire stock reservation from cart.
    2. For each item: read commission_pct_bps + kdv_pct_bps from ref_schema (single source of truth at sale time).
    3. Compute snapshot fields.
    4. Insert order + order_items rows + outbox event ecom.order.created.v1 in single tx.
  MarkPaid(ctx, orderID, pspRef) error
    Insert outbox event ecom.payment.captured.v1.
  MarkShipped(ctx, orderID, carrier, tracking) error
  MarkDelivered(ctx, orderID, deliveredAt time.Time) error
    Update orders.status='delivered', orders.delivered_at=deliveredAt.
    Insert outbox event ecom.order.delivered.v1 with payload:
      { order_id, user_id, market, delivered_at, items: [{seller_id, category_id, qty,
        unit_price_minor, commission_pct_bps, commission_amount_minor, kdv_amount_minor, seller_net_minor}, ...] }
  Cancel(ctx, orderID) error
  RefundFull(ctx, orderID) error  → emits ecom.order.refunded.v1
  RefundPartial(ctx, orderID, items) error

The delivered event MUST contain everything fin-svc needs to compute cashback total + per-seller payout net.
DO NOT compute cashback in core-svc; only emit the event with snapshots.

Add property test: For any cart with N items at random commission rates, sum(items[i].seller_net_minor) + sum(commission) + sum(kdv) == sum(unit*qty).

Report: file list, sample event payload JSON, test output.
```

**Verification / Done Criteria:**
- [ ] Order checkout → status transitions trigger expected outbox events.
- [ ] Snapshot of commission/KDV is stored in `order_items` (not recomputed on read).
- [ ] Property test of net + commission + kdv = gross passes.
- [ ] `ecom.order.delivered.v1` payload includes all fields fin-svc needs.

---

## Prompt 1.4 — PSP Adapter (Sipay primary, Craftgate backup, iyzico fallback) — v7 DETAILED

**Phase & Goal:** Phase 1. Implement payment.Service with three TR PSP adapters following the official Sipay/Craftgate/iyzico API contracts. Webhook handlers verify provider signatures and emit normalized `ecom.payment.captured.v1`.

**Copy-Paste Prompt:**

```
READ FIRST: CLAUDE.md § 9, ARCHITECTURE.md § 8.2 + § 8.5 (PSP API Reference).

Implement /internal/payment/ inside core-svc with the adapter pattern:
  /internal/payment/api.go      ← provider-agnostic Service interface
  /internal/payment/service.go  ← orchestration
  /internal/payment/sipay/
  /internal/payment/craftgate/
  /internal/payment/iyzico/
  /internal/payment/webhook.go  ← provider-agnostic dispatch

Service interface (provider-agnostic):
  CreatePaymentIntent(ctx, orderID, amountMinor, currency, cardOwnerInfo, threeDSReturnURL, idempotencyKey)
    → (PaymentIntent { providerRef, status, hppRedirectURL?, threeDSHTML? }, error)
  Capture(ctx, providerRef, idempotencyKey) → (Payment, error)
  Refund(ctx, providerRef, amountMinor, reason, idempotencyKey) → (Refund, error)
  TransferToSeller(ctx, sellerSubMerchantID, amountMinor, currency, idempotencyKey) → (Transfer, error)
  HandleWebhook(ctx, providerName, headers, body) → (NormalizedEvent, error)
  RegisterSubMerchant(ctx, sellerProfile) → (subMerchantID string, error)

— SIPAY ADAPTER —
Base URL (sandbox): https://provisioning.sipay.com.tr/ccpayment
Base URL (prod):    https://app.sipay.com.tr/ccpayment

Auth: Token-based. Get token via POST /api/token with merchant_key + app_id + app_secret.
Token TTL ~30 min; cache in Redis with refresh-on-401.

Endpoints:
  POST /api/getPos              — list installments + commission
  POST /api/paySmart3D          — initiate 3DS payment, returns HTML to render
  POST /api/payCompleted        — webhook receiver (we IMPLEMENT this on our side at /v1/payments/webhook/sipay)
  POST /api/refund              — refund a captured payment
  POST /api/checkstatus         — poll payment status
  POST /sub_merchant_register   — register a seller as sub-merchant
  POST /sub_merchant_pay        — split-payment: charge buyer, credit sub-merchant balance
  POST /sub_merchant_settlement — send sub-merchant balance to bank account

Webhook signature:
  Sipay sends `hash_key` header. Verify:
    expected = base64(hmacSha256(rawBody, app_secret))
    if expected != header → reject 401
  See https://docs.sipay.com.tr (sandbox creds: contact integration@sipay.com.tr)

Sandbox creds env names:
  SIPAY_MERCHANT_KEY, SIPAY_APP_ID, SIPAY_APP_SECRET, SIPAY_MERCHANT_ID

— CRAFTGATE ADAPTER —
Base URL (sandbox): https://sandbox-api.craftgate.io
Base URL (prod):    https://api.craftgate.io

Auth: HMAC-SHA256. Each request:
  x-api-key: <CRAFTGATE_API_KEY>
  x-rnd-key: <random_uuid>
  x-auth-version: 1
  x-signature: hmacSha256( apiKey + rndKey + apiSecret + uriPath + jsonBody, secret )

Endpoints:
  POST /payment/v1/payments              — create payment (3DS or non-3DS)
  POST /payment/v1/payments/{id}/refund  — refund
  POST /payment/v1/init-3ds              — initiate 3DS
  POST /payment/v1/complete-3ds          — finalize 3DS after returnURL hit
  POST /onboarding/v1/sub-merchants      — create sub-merchant (seller)
  POST /payout/v1/payout                 — payout to sub-merchant bank account
  GET  /payment/v1/payments/{id}         — query status

Webhook:
  POST to our /v1/payments/webhook/craftgate
  Signature: x-craftgate-signature header = hmacSha256(rawBody, CRAFTGATE_WEBHOOK_SECRET)

Sandbox creds env names:
  CRAFTGATE_API_KEY, CRAFTGATE_API_SECRET, CRAFTGATE_WEBHOOK_SECRET

— IYZICO ADAPTER (fallback) —
Base URL (sandbox): https://sandbox-api.iyzipay.com
Base URL (prod):    https://api.iyzipay.com

Auth: HMAC-SHA1 + Base64. Each request:
  Authorization: IYZWS <apiKey>:<base64Hash>
  x-iyzi-rnd: <random>
  hash = sha1( apiKey + rndKey + secretKey + jsonBody ) → base64

Endpoints:
  POST /payment/auth                      — payment with 3DS
  POST /payment/3dsecure/initialize       — start 3DS
  POST /payment/3dsecure/auth             — finalize 3DS
  POST /payment/refund                    — refund
  POST /payment/cancel                    — cancel before settlement
  POST /onboarding/sub-merchant           — create sub-merchant
  POST /payment/iyzipos/marketplace/payout— payout to sub-merchant

Sandbox creds env names:
  IYZICO_API_KEY, IYZICO_SECRET_KEY

— PROVIDER SELECTION —
Active provider: env PSP_PROVIDER=sipay|craftgate|iyzico (default sipay).
Per-payment override allowed via order metadata for A/B testing.

— NORMALIZED PAYMENT EVENT —
Adapter handlers normalize to internal struct:
  PaymentCaptured {
    OrderID         int64
    ProviderName    string
    ProviderRef     string
    AmountMinor     int64
    Currency        string
    CapturedAt      time.Time
    InstalmentCount int     // 1 = single payment
    CardLast4       string  // PCI-safe to log
    CardBrand       string  // visa, master, troy
    BinCountry      string  // ISO-3166
    RawPayload      json.RawMessage  // for audit
  }

Then writes outbox: ecom.payment.captured.v1 with this payload.

— TESTS —
1. Contract test: all 3 adapters satisfy the Service interface.
2. Webhook tests: replay sandbox webhook samples, verify signature pass/fail, normalization.
3. Idempotency: re-receive same webhook → no duplicate ecom.payment.captured.v1 in outbox.
4. Failover test: when PSP_PROVIDER changes mid-test, old in-flight payments use original provider's ref.
5. PCI safety: scan logs/errors → no full PAN, no CVV, no full track data.

Report: 3 adapter files, contract test, webhook signature samples, sandbox curl examples.
```

**Verification / Done Criteria:**
- [ ] All 3 PSP adapters compile + pass contract tests.
- [ ] Sipay sandbox webhook → ecom.payment.captured.v1 in outbox (verifiable end-to-end).
- [ ] Craftgate sub-merchant create + payout API exercised in sandbox.
- [ ] iyzico cancel-before-settlement path tested.
- [ ] Switching `PSP_PROVIDER` env requires only restart, no code change.
- [ ] No card PAN/CVV in any log line (verified by `grep -E "[0-9]{16}"` against logs).

---

## Prompt 1.5 — Caddy Routes for Phase 1 Endpoints

**Phase & Goal:** Phase 1. Verify all new endpoints are reachable through Caddy.

**Copy-Paste Prompt:**

```
Update /deploy/caddy/Caddyfile to ensure all Phase 1 endpoints route correctly:
  /v1/products, /v1/products/:id/*, /v1/categories/:id/commission → core-svc
  /v1/cart/* → core-svc
  /v1/orders/*, /v1/orders/:id/* → core-svc
  /v1/payments/webhook/sipay → core-svc
  /v1/payments/webhook/craftgate → core-svc
  /v1/payments/webhook/iyzico → core-svc
  /v1/shipping/webhook/{aras|yurtici|surat|mng|hepsijet|ptt} → core-svc
  /api/v1/seller/orders/:id/breakdown → core-svc (transparency)

After redeploying Caddy, run smoke tests on all routes.
Report curl outputs.
```

---

## Prompt 1.6 — Kargo Adapters (6 TR carriers) — v7 NEW

**Phase & Goal:** Phase 1. Implement shipping.Service with 6 TR kargo adapters following the official APIs. Webhook handlers update order status; "delivered" event triggers cashback + seller payout.

**Copy-Paste Prompt:**

```
READ FIRST: ARCHITECTURE.md § 8.4 + § 8.6 (Kargo API Reference).

Implement /internal/shipping/ inside core-svc with 6 carrier adapters:
  /internal/shipping/api.go      ← provider-agnostic Service interface
  /internal/shipping/service.go  ← orchestration + carrier selection
  /internal/shipping/aras/       ← SOAP+REST mixed
  /internal/shipping/yurtici/    ← SOAP only
  /internal/shipping/surat/      ← REST + JWT
  /internal/shipping/mng/        ← REST + API-Key
  /internal/shipping/hepsijet/   ← REST + OAuth2
  /internal/shipping/ptt/        ← SOAP

Service interface (provider-agnostic):
  CalculateRate(ctx, in RateRequest) → ([]CarrierQuote, error)
                  // returns quotes from ALL active carriers ranked by price+SLA
  CreateLabel(ctx, carrier string, in ShipmentInput) → (ShipmentResult, error)
  TrackShipment(ctx, carrier string, trackingNo string) → (TrackingState, error)
  CreateReturnLabel(ctx, carrier string, originalTrackingNo string) → (ShipmentResult, error)
  HandleWebhook(ctx, carrier string, headers, body) → (NormalizedShippingEvent, error)
  CancelShipment(ctx, carrier string, trackingNo string, reason string) → error

Per ARCHITECTURE.md § 8.6, each adapter wraps the official API:

— ARAS KARGO (SOAP+REST hybrid) —
Test base: https://test-customerservices.araskargo.com.tr/aras-rest-api/test/
Auth: HTTP Basic with (username, password, customer_code).
Implement REST endpoints (preferred):
  POST /api/v1/shipment              { sender, receiver, package_dims, cod_amount? }
  GET  /api/v1/shipment/{trackingNo}
  POST /api/v1/shipment/{trackingNo}/cancel  { reason }
  GET  /api/v1/rates                 { from_postal, to_postal, weight }
NO native webhook → /internal/shipping/aras/poller.go runs a 5-min cron polling
all 'in_transit' shipments and updates state. On state change → emit
ecom.shipping.<state>.v1 via outbox.

— YURTİÇİ KARGO (SOAP) —
Test WSDL: https://testservis.yurticikargo.com/KOPSWebServices/services/ShippingOrderServiceV2?wsdl
Auth: WS-Security UsernameToken (username + password).
SOAP operations: createShippingOrder, queryShipment, cancelShippingOrder, getShipmentStatus.
NO native webhook → polling cron (same as Aras).

— SÜRAT KARGO (REST + JWT) —
Test base: https://uatxapi.suratkargo.com.tr
Auth: POST /api/auth/login → JWT (TTL 24h, cache).
Endpoints:
  POST /api/shipment/create      { senderInfo, receiverInfo, parcelInfo }
  GET  /api/tracking/{barcode}
  POST /api/return/create        { originalBarcode, reason }
Native webhook: POST /v1/shipping/webhook/surat
Signature: X-Surat-Sign header = hmacSha256(rawBody, SURAT_WEBHOOK_SECRET)

— MNG KARGO (REST + API-Key) —
Test base: https://testapi.mngkargo.com.tr/mngapi
Auth: API-Key header + JWT bearer (POST /api/login).
Endpoints:
  POST /api/standardcmdapi/createOrder
  GET  /api/cargotracking/{trackingNo}
  POST /api/standardcmdapi/cancelOrder
Native webhook: POST /v1/shipping/webhook/mng
Signature: X-MNG-Signature = hmacSha256(rawBody, MNG_WEBHOOK_SECRET)

— HEPSİJET (REST + OAuth2) —
Test base: https://api-test.hepsijet.com
Auth: OAuth2 client_credentials grant (POST /v1/auth/token; cache token).
Endpoints:
  POST /v1/shipments
  GET  /v1/shipments/{id}
  POST /v1/shipments/{id}/return
  POST /v1/shipments/{id}/cancel
Native webhook: POST /v1/shipping/webhook/hepsijet
Auth: bearer token in webhook header validated against same OAuth2 token

— PTT KARGO (SOAP) —
Test WSDL: https://wstest.ptt.gov.tr/MusteriHizmetleriWS/services?wsdl
Auth: HTTP Basic + customer_code.
SOAP operations: BarkodOlustur, KargoTakip, IadeOlustur, KargoIptal.
NO native webhook → daily batch reconcile (less critical than e-commerce carriers).

— NORMALIZED SHIPPING EVENT (after webhook/poll dispatch) —
ShippingStateChanged {
    OrderID         int64
    ShipmentID      int64
    Carrier         string
    TrackingNumber  string
    State           string  // 'created'|'picked_up'|'in_transit'|'out_for_delivery'|'delivered'|'returned'|'cancelled'|'failed'
    OccurredAt      time.Time
    Location        string  // city or hub name
    RawPayload      json.RawMessage
}

When State = 'delivered' → core-svc.order updates orders.delivered_at, then emits
ecom.order.delivered.v1 (the trigger for cashback + seller payout in fin-svc).

— SCHEMA additions —
ref_schema.shipping_carriers (carrier_code, name_tr, name_en, supports_cod, supports_return,
                              supports_webhook BOOL, active BOOL)
ref_schema.shipping_rules    (seller_id NULL=platform_default, carrier_code, free_threshold_minor,
                              flat_rate_minor, currency, active)
shipping_schema.shipments    (id, order_id, carrier, tracking_number, label_pdf_b2_key,
                              estimated_delivery, cost_minor, currency, state, last_state_at,
                              created_at, updated_at)
shipping_schema.shipment_events (id, shipment_id, state, occurred_at, location, raw JSONB)

— TESTS —
1. Contract test: all 6 adapters satisfy the Service interface.
2. Polling cron (Aras+Yurtiçi+PTT): mock SOAP/REST responses, verify state transitions emit events.
3. Webhook tests: replay sample payloads from each carrier, verify signature pass/fail.
4. CalculateRate aggregation: 3 carriers return quotes → service returns sorted by price+SLA.
5. Failover: when primary carrier API returns 5xx for > 5 min, next-cheapest is used.

Report: 6 adapter folders, contract test, sample webhook payloads (anonymized), failover log.
```

**Verification / Done Criteria:**
- [ ] All 6 carrier adapters compile + pass contract tests.
- [ ] Polling cron picks up state changes within 5 min for Aras/Yurtiçi/PTT.
- [ ] Webhook signature validation passes for Sürat/MNG/HepsiJet sample payloads.
- [ ] Delivery state change triggers `ecom.order.delivered.v1` in outbox.
- [ ] CalculateRate returns multi-carrier quotes within 2s p95.

---

# PHASE 2 — FinTech Core, Cashback Engine, Seller Payout, Wallet

## Prompt 2.1 — Create wallet Module (Multi-Currency Chart of Accounts)

**Phase & Goal:** Phase 2. wallet module exposes ledger primitives + balance reads.

**Copy-Paste Prompt:**

```
READ FIRST: LEDGER_GUIDE.md (entire file), DATA_DICTIONARY.md § 8.

Implement /internal/wallet/ inside fin-svc.

Service interface:
  Post(ctx, in PostInput) (txnID int64, error)
  PostInTx(ctx, tx pgx.Tx, in PostInput) (txnID int64, error)
  GetBalance(ctx, accountID) (int64, error)
  FindAccount(ctx, type string, currency string) (accountID int64, error)
  OpenOrFindUserWallet(ctx, userID, currency) (accountID int64, error)
  FindOrOpenSellerPayable(ctx, sellerID, currency) (accountID int64, error)   ← v5

PostInput { Type, Reference, IdempotencyKey, Market, Currency, Entries []Entry }
Entry { AccountID, Direction, AmountMinor }

Implementation MUST follow the mandatory pattern in LEDGER_GUIDE.md § 6.

Property tests (gopter):
  - Per-currency D=C invariant (1000+ random ops)
  - Idempotency: applying the same PostInput twice yields one ledger transaction
  - No mixed-currency: any test that synthesizes a mixed-currency PostInput MUST cause a rollback

Report: file list, property test output.
```

**Verification / Done Criteria:**
- [ ] Property tests pass 1000+ iterations.
- [ ] All ledger writes funnel through wallet.Post; depguard verifies no module bypasses.

---

## Prompt 2.2 — Implement cashback-engine Module (THE CENTERPIECE) — v5 LOCKED MODEL

**Phase & Goal:** Phase 2. cashback-engine consumes `ecom.order.delivered.v1`, creates a FROZEN plan + 24 scheduled payments + the equity↔obligation ledger move, all idempotently.

**Copy-Paste Prompt:**

```
READ FIRST: CLAUDE.md § 4.7, LEDGER_GUIDE.md § 7, DATA_DICTIONARY.md § 8.

Implement /internal/cashback/ inside fin-svc (v6 PERPETUAL model).

const ReferenceInterestRateBpsConst = 5000  // v6 LOCKED = %50.00. Changing requires constitution update.

Domain (v6):
  Plan { ID, OrderID, UserID, MonthlyAmountMinor, Currency, ReferenceInterestRateBps,
         StartDate, Status, DeliveredAt, Market, CommissionSnapshot, IdempotencyKey, ... }
  Payment { ID, PlanID, PeriodYYYYMM, ScheduledDate, PaidDate, AmountMinor, Status,
            LedgerTransactionID, IdempotencyKey, AttemptCount, ... }

Service interface:
  CreatePlanForOrder(ctx, ev OrderDeliveredEvent) error      ← idempotent on (order_id)
  RunMonthlyPayments(ctx, runDate time.Time) error           ← idempotent per (plan_id, period_yyyymm)
  CancelPlan(ctx, planID, reason string) error               ← reverses paid + sets status='cancelled' (cron will skip)
  PartialRefund(ctx, planID, refundFraction float64, reason string) error   ← reduces monthly_amount_minor (audit-logged)
  GetPlanByOrderID(ctx, orderID) (*Plan, error)

CreatePlanForOrder logic per LEDGER_GUIDE.md § 7.1 (v6):
  1. Idempotency: if plan exists for order_id → no-op.
  2. commissionMinor = sum(items[i].CommissionAmountMinor)  ← from event payload, NOT recomputed
  3. yearlyYieldMinor = commissionMinor * ReferenceInterestRateBpsConst / 10000
  4. monthlyMinor = yearlyYieldMinor / 12       ← v6: NO total amount, NO remainder, perpetual
  5. unlockAt = pkg/timex.AddBusinessDays(ev.DeliveredAt, 3, ref_schema.business_calendars[market])
  6. startDate = unlockAt   ← NO end_date; perpetual
  7. Single SERIALIZABLE tx:
     a. INSERT plans row (frozen by trigger; only status mutable)
     b. NO payment rows pre-seeded — cron creates them month by month.
     c. NO ledger move at plan creation (perpetual model accrues period-by-period).
     d. INSERT outbox fin.cashback.plan.created.v1

RunMonthlyPayments per LEDGER_GUIDE.md § 7.2 (v6):
  period := yyyymm(runDate)  // e.g., 202607
  SELECT active plans WHERE start_date <= runDate (batch up to 1000)
  For each plan, in own tx:
     1. INSERT cashback_schema.payments row for (plan_id, period, monthly_amount_minor, 'scheduled')
        — UNIQUE constraint on (plan_id, period_yyyymm) makes this idempotent.
     2. wallet.PostInTx (TRY_COIN-only):
        D equity:cashback_distribution:TRY_COIN  amount=plan.MonthlyAmountMinor
        C liability:wallet:user_<id>:TRY_COIN     amount=plan.MonthlyAmountMinor
     3. Mark payment as 'paid', record ledger_transaction_id.
     4. INSERT outbox fin.cashback.payment.posted.v1.

CancelPlan per LEDGER_GUIDE.md § 7.4 (v6):
  1. Sum paid coin so far for this plan.
  2. Reversal: D liability:wallet:user / C equity:cashback_distribution for paid amount.
  3. UPDATE plans SET status='cancelled' (allowed; only status mutable).
  4. Future cron runs SKIP this plan (SELECT WHERE status='active').
  5. Mopro's commission principal in equity:retained_commission:TRY is implicitly
     released — no explicit ledger move needed (no upfront obligation in v6).

PartialRefund (v6):
  1. Compute new_monthly = old_monthly * (1 - refundFraction)
  2. INSERT plans_history audit row (BEFORE the UPDATE, because the trigger checks for it).
  3. UPDATE plans SET monthly_amount_minor = new_monthly (allowed via the audit-trail exception).
  4. Future cron runs use new monthly amount.

Property tests (gopter, v6):
  - For random (price, commissionPctBps): monthlyMinor = round(price × pct × 5000 / 10000 / 10000 / 12)
    matches CreatePlanForOrder output deterministically.
  - After N cron runs (N arbitrary), user wallet credited exactly N × plan.MonthlyAmountMinor.
  - UPDATE on plan.monthly_amount_minor without plans_history row raises (immutability).
  - Replay of same delivery event → exactly one plan, exactly one payment per period.

Wire the consumer: fin-svc.event-consumer subscribes to ecom.order.delivered.v1 and dispatches to CreatePlanForOrder.

Report: file list, property test output, sample event consumption log.
```

**Verification / Done Criteria:**
- [ ] Property tests pass 500+ iterations.
- [ ] Re-emitting the same delivered event creates exactly one plan.
- [ ] Cancellation reverses correctly per LEDGER_GUIDE § 7.4.
- [ ] Mutating plan core fields is rejected by trigger.

---

## Prompt 2.3 — Implement seller-payout-engine Module — NEW v5

**Phase & Goal:** Phase 2. seller-payout-engine consumes the SAME `ecom.order.delivered.v1`, creates one FROZEN payout per (order, seller), schedules unlock_at = delivered + 3 BD, then a daily cron initiates PSP transfer.

**Copy-Paste Prompt:**

```
READ FIRST: CLAUDE.md § 4.8, LEDGER_GUIDE.md § 8, DATA_DICTIONARY.md § 9.

Implement /internal/sellerpayout/ inside fin-svc.

const PayoutDelayBusinessDays = 3  // v5 LOCKED.

Domain:
  Payout { ID, OrderID, SellerID, AmountMinor, Currency, DeliveredAt, UnlockAt, PaidAt,
           PspTransferID, Status, Market, LedgerTransactionID, IdempotencyKey, ... }

Service interface:
  SchedulePayoutForOrder(ctx, ev OrderDeliveredEvent) error      ← idempotent per (order_id, seller_id)
  RunDailyPayouts(ctx, runDate time.Time) error                  ← idempotent per payout_id
  ReconcileWithPSP(ctx, payoutID) error                          ← used when webhook missing
  CancelPayout(ctx, payoutID, reason string) error               ← refund/order-cancel path

SchedulePayoutForOrder logic:
  1. aggregateBySeller(ev.Items): map[seller_id] sum(items[i].SellerNetMinor)
  2. unlockAt = pkg/timex.AddBusinessDays(ev.DeliveredAt, 3, calendarFor(ev.Market))
  3. For each (sellerID, netMinor): if payout doesn't exist for (order, seller), INSERT.
  4. NO ledger move at schedule time (escrow already holds funds from order capture).

RunDailyPayouts logic:
  SELECT WHERE unlock_at <= today AND status='scheduled' LIMIT 1000.
  For each:
    a. PSP InitiateTransfer (idempotency_key = payout.IdempotencyKey).
    b. wallet.PostInTx:
         D liability:seller_payable:TRY  amount=p.AmountMinor
         C asset:bank:escrow:TRY         amount=p.AmountMinor
    c. Mark payout 'processing', store psp_transfer_id and ledger_transaction_id.
    d. Insert outbox fin.seller.payout.posted.v1.

ReconcileWithPSP:
  Fetches PSP GET /transfers/<id>; updates status to 'paid' or 'failed' + records reasons.

CancelPayout:
  Reversal: D asset:bank:escrow:TRY / C liability:seller_payable:TRY.
  UPDATE payout SET status='reversed' (only status is mutable; trigger blocks core fields).

Property tests (gopter):
  - For random delivered_at across 5 years, payout.UnlockAt == AddBusinessDays(delivered_at, 3, TR_calendar)
  - Per-seller aggregation: items[a,b] both seller=42 → ONE payout row with sum(net)
  - UPDATE on payout.amount_minor raises (immutability)
  - Re-receiving the same delivered event does NOT create duplicate payouts

Wire the consumer: fin-svc.event-consumer subscribes to ecom.order.delivered.v1 and dispatches to SchedulePayoutForOrder (same event, second consumer group).

Report: file list, property test output, sample payout schedule.
```

**Verification / Done Criteria:**
- [ ] Property tests pass.
- [ ] Mutating payout core fields is rejected.
- [ ] One payout per (order, seller); duplicate event creates no extra rows.

---

## Prompt 2.4 — Weekly Ledger Reconciliation Cron (Phase 2.4)

// v7.1: shell scripts replaced by fin-svc Go cron for outbox + role parity.
// See Phase 2.4 reconciliation report for full justification.
// Checks 3/4/5 (escrow, seller_payable, user wallet) deferred to Phase 5.

**Phase & Goal:** Phase 2. The weekly reconciliation cron (Go, inside fin-svc) that verifies
per-currency D=C and cashback obligation sums match. Implemented as `internal/reconcile.WeeklyCron`.

**Copy-Paste Prompt:**

```
READ FIRST: LEDGER_GUIDE.md § 9, CLAUDE.md §5 (cross-schema exception for internal/reconcile).

The reconcile cron runs in internal/reconcile.WeeklyCron, scheduled "0 5 3 * * 0"
(Sundays 03:05 Europe/Istanbul). Connects as reconcile_user (RECONCILE_DATABASE_URL).

On any invariant failure:
  1. Inserts a ledger_alerts row (always, for audit) with alert_type='reconciliation_drift'.
  2. Updates wallet_schema.system_state SET read_only=TRUE (if LEDGER_RECONCILE_DRY_RUN=false).
  3. Triggers PagerDuty via PAGERDUTY_ROUTING_KEY + PAGERDUTY_API.
  4. Emits fin.reconciliation.drift_critical.v1 outbox event.
  5. wallet.PostInTx returns ErrSystemReadOnly until: mopro clear-read-only.

Report: implementation, test output, build output.
```

---

## Prompt 2.5 — Cashback Monthly Cron + Seller Payout Daily Cron Wiring

<!-- v7.1 deviation: system cron /etc/cron.d replaced by in-process Go cron
(robfig/cron/v3) for outbox + role parity. See Phase 2.5 implementation report
for full justification. Healthchecks.io pings are made by the in-process pinger;
UUIDs in env vars follow HEALTHCHECK_*_UUID convention (NewFromUUID builds full URL). -->

**Phase & Goal:** Phase 2. Wire the two crons to fire on schedule with healthchecks.io ping.

**Copy-Paste Prompt:**

```
READ FIRST: ARCHITECTURE.md § 4.2, INFRASTRUCTURE.md § 9.3.

Add to /etc/cron.d/mopro-fin:
  0 2 1 * * deploy docker exec fin-svc /app/app cashback-cron --month $(date -u +%Y-%m) && curl -sf https://hc-ping.com/$HEALTHCHECK_CASHBACK_CRON_UUID
  30 2 * * * deploy docker exec fin-svc /app/app seller-payout-cron --date $(date -u +%Y-%m-%d) && curl -sf https://hc-ping.com/$HEALTHCHECK_SELLER_PAYOUT_CRON_UUID

The CLI subcommands `cashback-cron` and `seller-payout-cron` invoke RunMonthlyPayments / RunDailyPayouts respectively.

Both healthcheck UUIDs configured in healthchecks.io with grace period 30 minutes; alert on missing ping → SEV2 PagerDuty.

Report cron file, healthcheck dashboard screenshot description.
```

---

# PHASE 3 — Distributed Sagas & Async Jobs

## Phase 3.0 Deviation Note (pre-flight, inserted 2026-05-16)

Before Phase 3.1 implementation began, a pre-flight event inventory audit (Phase 3.0)
was performed. Six speculative event type strings with zero production call sites were
discovered in `internal/wallet/service.go` (outboxEventType switch):

  Deleted (no call sites):
    - fin.cashback.reversal.posted.v1
    - fin.commission.accrual.posted.v1
    - fin.fx.outbound.posted.v1
    - fin.fx.inbound.posted.v1

  Renamed (confirmed active via explicit EventType override in run_daily.go):
    - fin.seller.payout.posted.v1 → fin.seller.payout.batch.paid.v1

Additionally, a defensive `default` case in `internal/payment/sipay/webhook.go` emitted
`ecom.payment.unknown.v1` for unrecognised Sipay status codes. This was changed to return
an error (HTTP 400) before outbox insertion, eliminating the speculative event type.

Phase 3.0 deliverables committed:
  1. notification_schema.slack_sent migration (postgres-ecom + pg-test)
  2. internal/eventbus/registry.go — authoritative event type registry (17 entries)
  3. Wallet outboxEventType cleanup (4 deleted, 1 renamed)
  4. Sipay webhook unknown-type guard (error before outbox, no row written)
  5. pkg/slack — Incoming Webhook client (modelled on pkg/pagerduty)
  6. internal/notification — reconcile_consumer.go + dedup.go
  7. cmd/jobs-svc/main.go — wired reconcile-drift consumer
  8. Tests: C (dedup), D (503→200 retry), E (unknown type → 400)
  9. ARCHITECTURE.md steps 5-8 corrected; steps 14-15 event name updated; registry link added
  10. LEDGER_GUIDE.md:667 event name updated; DEVELOPMENT.md § 19 Naming Authority Rule added

---

## Prompt 3.1 — Wire ecom.order.delivered.v1 → BOTH Cashback Plan AND Seller Payout

**Phase & Goal:** Phase 3. The single delivered event has TWO consumer groups (cashback-engine and sellerpayout-engine). Verify both fire on every delivered order, idempotently.

**Copy-Paste Prompt:**

```
READ FIRST: ARCHITECTURE.md § 5, LEDGER_GUIDE.md § 7.1, § 8.1.

Configure fin-svc.event-consumer with TWO Redis consumer groups on stream ecom.order.delivered.v1:
  - Group "cashback-engine"  → handler: cashback.CreatePlanForOrder
  - Group "sellerpayout-engine" → handler: sellerpayout.SchedulePayoutForOrder

Both groups use XREADGROUP COUNT 100 BLOCK 5000.
Both handlers MUST be idempotent (per their own key structure).
On handler error: XACK is NOT called → message stays in PEL for redelivery.
XAUTOCLAIM goroutine per consumer group: reclaims messages idle > 5 min from crashed consumers.
Attempt counter: wallet_schema.event_delivery_attempts records every dispatch outcome.
After 3 failures on the same message: WARN log "DLQ candidate (not yet inserted — Phase 3.2)".

[v7.1 deviation: DLQ insertion (XACK to break retry loop, event_dlq table, Slack alert)
 is deferred to Phase 3.2. Phase 3.1 ships XAUTOCLAIM + attempt counter + WARN-at-3.]

Add integration test: simulate one delivered event for an order with 3 items from 2 sellers.
Assert (v6 perpetual model):
  - 1 cashback plan row created (status='active')
  - 0 cashback payment rows created (payments fire from monthly cron, NOT at plan creation)
  - 2 seller_payout rows created (one per seller, status='scheduled')
  - event_delivery_attempts: >= 2 success rows (one per consumer group)
Re-emit the SAME event:
  - All counts unchanged (idempotency holds)
Run cashback monthly cron once:
  - cashback_payments: COUNT = 1 (status='paid')
Run cashback monthly cron again same period:
  - cashback_payments: still COUNT = 1 (idempotent — plan already distributed this period)

NOTE: "24 cashback payment rows" in the original spec was pre-v6 fixed-term model.
In the v6 PERPETUAL model there is NO total_payments pre-allocation. 0 rows at plan creation
is the CORRECT invariant. See CLAUDE.md § 4.7 (PERPETUAL MODEL, no end_date, no fixed term).

Report: configuration, test output, Redis XINFO GROUPS output.
```

**Verification / Done Criteria:**
- [ ] Both consumer groups receive every delivered event.
- [ ] Replay creates no duplicates.

---

## Prompt 3.2 — DLQ Handling ✅ COMPLETE (2026-05-16)

**Phase & Goal:** Phase 3. Dead-letter queue for permanently failed events; CLI replay tools.

**Implementation summary:**
- `wallet_schema.event_dlq` table (migration 72) with `UNIQUE(consumer_group, original_message_id)` for idempotent inserts; `dlq_user` Postgres role with least-privilege grants.
- `GRANT DELETE ON event_delivery_attempts TO reconcile_user` (migration 73) for weekly cleanup.
- `DLQRepository` interface + `pgxDLQRepository` with `InsertIfThreshold` (READ COMMITTED tx, error_history snapshot, ON CONFLICT DO NOTHING).
- `insertDLQIfThreshold` called synchronously in `dispatchMessage` defer, BEFORE XACK. DLQ failure → message stays in PEL. `DLQAlreadyExists` → XACK retry without Slack.
- SEV3 alert on first insertion; SEV2 if >10 DLQ rows in 10-min window (per-topic `sync.Map` dedup, 10-min TTL).
- `xackClient` interface as testable seam for unit tests without miniredis.
- `mopro dlq list|inspect|replay|dismiss` subcommands with `--dry-run`, `--json`, `--by`, `--confirm` flags. XADD-first replay ordering (new message before `MarkReplayed`).
- `reconcile.WeeklyCron` cleans `event_delivery_attempts` rows older than 7 days.
- CLAUDE.md §5: fin-svc → Slack direct alerting exception documented.
- 7 unit tests, 5 integration tests, 5 CLI tests, 3 e2e/property tests (including mandatory `TestE2E_ReplayReloops`).

**Copy-Paste Prompt:**

```
READ FIRST: DISASTER_RECOVERY.md § 5.

Implement DLQ behavior:
  After 3 redelivery attempts of the same event, the consumer:
    1. Inserts the event into wallet_schema.event_dlq table (id, original_topic, original_message_id, payload, attempt_count, error_history, created_at)
    2. XACK the original to stop redelivery storm
    3. Emits Slack alert SEV3 (or SEV2 if >10 messages in DLQ for the same topic in 10 min)

Add CLI commands to /cmd/mopro/main.go:
  mopro dlq list [--topic <name>] [--since "<duration>"]
  mopro dlq inspect <dlq_id>
  mopro dlq replay <dlq_id> [--dry-run]
  mopro dlq replay --topic <name> --since "<duration>" --confirm

Replay re-publishes the original event to the original stream with the original idempotency key, so consumers see no duplicate effects.

Report: DLQ schema, CLI invocations, sample alert payload.
```

Next: **Prompt 3.3 — Outbox Publisher Productionize** (backpressure, Redis flap handling).

---

## Prompt 3.3 — Outbox Publisher Productionize

**Phase & Goal:** Phase 3. Make the outbox-publisher robust against backpressure, Redis flaps, and partial failures.

**Copy-Paste Prompt:**

```
READ FIRST: LEDGER_GUIDE.md § 5, DISASTER_RECOVERY.md § 5.

Productionize /internal/outbox/publisher.go:
  - Adaptive batch size (start at 100, scale to 500 if no errors, fall back on transient errors).
  - Exponential backoff on Redis errors (1s, 2s, 4s, 8s capped at 60s).
  - Metric mopro_<svc>_outbox_lag_seconds (oldest unpublished row age).
  - Alert if lag > 60s.
  - Graceful shutdown drains in-flight batch before exit.

Add chaos test: force Redis down for 30s during a publishing burst; verify no rows are lost; verify catch-up after recovery.

Report: code, chaos test output, lag metric example.
```

---

## Prompt 3.4 — Anti-Fraud ML Pipeline (Kategori Sahteciliği) — v7 NEW

**Phase & Goal:** Phase 3+. Build the anti-fraud module that catches sellers who list a high-commission category product as a low-commission category to game the cashback formula. Two ML models + manual review queue.

**Threat model (kritik):** v6 modelinde aylık coin = (price × commission_pct × %50) / 12. Bir satıcı 1000 TL'lik bir telefonu (gerçek %7 komisyon) "Atkı, Bere" kategorisinde (%20 komisyon) listelerse, alıcı yanlış fazla coin alır, Mopro yanlış fazla yükümlülük taşır. Bu doğrudan finansal saldırıdır.

**Copy-Paste Prompt:**

```
READ FIRST: CLAUDE.md § 4.7 (cashback formula sensitivity), DATA_DICTIONARY.md § 6 (catalog).

Implement /internal/antifraud/ inside core-svc (NOT fin-svc — this is product
classification, not financial). Module owns:
  /internal/antifraud/api.go
  /internal/antifraud/service.go
  /internal/antifraud/nlp/        ← text classification client
  /internal/antifraud/vision/     ← image classification client
  /internal/antifraud/rules/      ← deterministic heuristic rules
  /internal/antifraud/queue/      ← review queue repository

Service interface:
  ScoreNewListing(ctx, productID, categoryID, title, description, imageKeys[]) → (Decision, error)
  Decision { Score 0-100, AutoAction 'auto_approve'|'auto_reject'|'manual_review', Reasons []string }
  RescoreOnUpdate(ctx, productID) → recompute when seller edits
  ApproveListing(ctx, productID, reviewerID) → release product to live
  RejectListing(ctx, productID, reviewerID, reason) → notify seller

Architecture decision: ML INFERENCE runs in jobs-svc (CPU-bound, isolated).
core-svc.antifraud calls jobs-svc HTTP /internal/v1/antifraud/score.

═══ MODEL 1: NLP TEXT CLASSIFIER ═══
Task: Given (title + description + brand), predict the category.
Compare predicted vs. seller-claimed category → mismatch score.

Model selection (May 2026 baseline):
  - PRIMARY: dbmdz/bert-base-turkish-cased fine-tuned on TR e-commerce data.
    Why: best F1 on Turkish, runs on CPU 200ms p95, 110M params.
  - ALT: xlm-roberta-base (if multilingual needed for Phase 7+).
  - Frame as multi-class classification over the 42 ref_schema.categories.

Training data:
  - Bootstrap: scrape 100K product titles from Trendyol / Hepsiburada with category
    labels (legal grey area; consult counsel; better: use public datasets like
    GittiGidiyor open dataset or buy from a vendor like Sutucu Datasets).
  - Active learning: as Mopro accumulates real listings + manual review verdicts,
    add to training set. Retrain monthly.

Serving:
  - Convert to ONNX format → run via /jobs-svc with onnxruntime-go.
  - Container: gcr.io/distroless/cc-debian12:nonroot + onnxruntime native lib.
  - Bundled model file: /models/tr-cat-bert-v1.onnx (~440 MB; mounted volume).

Output: { predictedCategoryID, confidence 0-1, top5: [{cat,prob}, ...] }

═══ MODEL 2: VISION IMAGE CLASSIFIER ═══
Task: Given product image(s), predict the category.
Cross-check against seller's claim AND NLP model.

Model selection:
  - PRIMARY: efficientnet-b0 fine-tuned (5M params, fast on CPU 150ms p95).
  - ALT: mobilenet-v3-large for even faster inference.
  - Multi-label: an image can match multiple categories with different probabilities.

Training data:
  - Bootstrap: ImageNet pretrained → fine-tune on 50K labeled product images
    (same source as NLP).
  - Augmentation: rotation, crop, color jitter (typical product photo variations).

Serving: same ONNX pattern in jobs-svc.

═══ MODEL 3: DETERMINISTIC RULES ═══
Independent of ML:
  - Rule 1: Title contains a brand name strongly associated with another category.
    Example: title "iPhone 15" + claimed_category="Atkı, Bere" → flag.
    Maintain ref_schema.brand_category_hints (brand TEXT, expected_category_id).
  - Rule 2: Price out of range for the claimed category.
    Maintain ref_schema.category_price_ranges (category_id, min_minor, max_minor, currency).
    1000 TL "kalem" = suspicious.
  - Rule 3: Commission rate exploitation pattern.
    If commission_pct(claimed) > commission_pct(predicted_by_nlp) → high suspicion
    (because attacker benefits when claimed > true).
  - Rule 4: New seller with high-cashback listings.
    First 30 days, all listings with predicted commission > %15 → manual review.

═══ SCORE COMPUTATION ═══
Combined score (0=safe, 100=fraud certain):
  ml_disagreement_score = (1 - nlp_confidence_for_claimed_category) * 50
                        + (1 - vision_confidence_for_claimed_category) * 30
  rule_score = sum of rule weights (each rule 0-30 points)
  final_score = clamp(ml_disagreement_score + rule_score, 0, 100)

Decision matrix:
  score ≤ 20  → auto_approve, listing goes live immediately
  21-60       → manual_review, listing pending until reviewer acts
  ≥ 61        → auto_reject, seller notified with reason, can re-submit

═══ MANUAL REVIEW QUEUE ═══
Queue rendering:
  /internal/antifraud/queue/repository.go
  Table: antifraud_schema.review_queue (id, product_id, score, reasons JSONB,
         status, assigned_to, reviewed_at, decision, decision_reason, created_at)

Admin UI: simple Vue/React page under admin.moproshop.com:
  - List of pending items (sorted by created_at)
  - Click → product details + ML scores + rule hits + image gallery
  - "Approve" / "Reject (with reason)" buttons
  - Bulk actions: select multiple, batch approve/reject

SLA: items in queue > 24h → page on-call (high false positive cost: seller waits).

═══ FEEDBACK LOOP ═══
Every manual decision is appended to:
  antifraud_schema.training_feedback (product_id, claimed_cat, true_cat,
      reviewer_decision, created_at)

Monthly cron: re-export training_feedback + retrain models offline (Jupyter
notebook in /ml/notebooks/), produce new ONNX, swap atomically.

═══ TESTS ═══
1. Unit: rules trigger correctly for known patterns.
2. Integration: mock ML inference, verify decision matrix.
3. Property: monotonicity — higher rule_score never decreases final decision severity.
4. Adversarial: seed 100 known fraud listings (synthetic) and 100 known good listings,
   measure precision/recall. Target: precision ≥ 0.90, recall ≥ 0.85.
5. Performance: p95 ScoreNewListing < 800ms (incl. 2 ML round-trips to jobs-svc).

═══ SCHEMA ADDITIONS ═══
catalog_schema.products: ADD COLUMN antifraud_status TEXT DEFAULT 'pending'
                              CHECK IN ('pending','approved','rejected','live')
                         ADD COLUMN antifraud_score INTEGER

antifraud_schema (new):
  - review_queue (above)
  - training_feedback (above)
  - rules_config: deterministic rule weights (mutable; admin UI to tune)
  - model_versions: which ONNX file is active (for rollback)

ref_schema additions:
  - brand_category_hints
  - category_price_ranges

═══ CRON ═══
- antifraud-rescore-cron (daily 03:00 UTC): re-score all 'pending' or 'live' products
  whose category_rules updated in last 24h (catches ref data changes).

═══ ESCALATION ═══
If a product reaches 'live' status and IS later detected as fraudulent
(buyer reports, manual audit), fin-svc.cashback CancelPlan + commission Reversal
+ block the seller, notify legal team. See LEDGER_GUIDE.md § 7.4.

Report: module structure, sample inference call, sandbox test scores
(precision/recall on adversarial set), admin UI wireframe.
```

**Verification / Done Criteria:**
- [ ] NLP + Vision models served by jobs-svc, both < 250ms p95.
- [ ] Deterministic rules implemented and unit-tested.
- [ ] Combined score logic deterministic, property-tested.
- [ ] Adversarial set: precision ≥ 0.90, recall ≥ 0.85.
- [ ] Admin review UI live; SLA cron pages on > 24h backlog.
- [ ] Monthly retraining notebook checked in; documented run process.

---

# PHASE 4 — Flutter Mobile

## Prompt 4.1 — Initialize Flutter Project with Riverpod 2 + i18n

**Phase & Goal:** Phase 4. Mobile app skeleton with state management, theming, localization-ready.

**Copy-Paste Prompt:**

```
READ FIRST: ARCHITECTURE.md § 1, DEVELOPMENT.md § 15.

Create /mobile (Flutter project) with:
  - Flutter 3.x, Dart 3.x
  - flutter_riverpod 2.x
  - go_router for navigation
  - dio for HTTP
  - easy_localization for i18n
  - flutter_secure_storage for tokens
  - cached_network_image
  - uuid (for idempotency-key generation)

Folder layout:
  /mobile/lib/
    main.dart
    app/             (theme, router, env)
    core/            (network, storage, errors)
    features/
      auth/          (login, register, otp)
      home/          (anasayfa, banner)
      catalog/       (categories, product detail with cashback preview)
      cart/
      checkout/
      orders/
      wallet/        (cashback timeline, balance)
      seller/        (panel webview placeholder)
      support/
      profile/
    shared/
      widgets/       (atomic design)
      theme/

/mobile/assets/translations/
  tr-TR.json    ← seeded with all UI strings in Turkish
  en-US.json    ← seeded with English
  de-DE.json    ← placeholder
  ar-AE.json    ← placeholder

NO hardcoded user-facing strings in Dart files; ALL via context.tr('key').

Cashback preview key in catalog product detail:
  tr-TR: "Bu üründen aylık {monthly} Mopro Coin alacaksınız — SÜRESİZ."
  en-US: "You'll receive {monthly} Mopro Coin per month from this product — FOREVER."

Report: file tree, sample widget using context.tr.
```

---

## Prompt 4.2 — Dio Client + Interceptors (Locale, Auth, Idempotency, Trace, Retry)

**Phase & Goal:** Phase 4. HTTP client wired with all required cross-cutting concerns.

**Copy-Paste Prompt:**

```
Create /mobile/lib/core/network/dio_client.dart with these interceptors:
  1. AuthInterceptor: adds Authorization: Bearer <jwt> from secure storage.
  2. LocaleInterceptor: adds Accept-Language: <user_locale> (e.g., tr-TR).
  3. IdempotencyInterceptor: for POST/PUT/PATCH, generates UUIDv7, attaches X-Idempotency-Key header.
  4. TraceInterceptor: generates client-side trace_id, sets X-Trace-Id; reads X-Trace-Id from response.
  5. RetryInterceptor: retries idempotent requests on 5xx with exponential backoff (250ms, 500ms, 1s); max 3 retries; respects X-Retry-After.
  6. ErrorMappingInterceptor: maps server error codes to AppError (typed) for UI to render.

Base URL from env: API_BASE_URL=https://api.moproshop.com.

Add tests with mock server for each interceptor.

Report: code, test output.
```

---

## Prompt 4.3 — Wallet + Cashback Timeline Widget (Atomic Design)

**Phase & Goal:** Phase 4. The wallet screen showing TRY_COIN balance + perpetual monthly cashback amount per active plan.

**Copy-Paste Prompt:**

```
Implement /mobile/lib/features/wallet/:
  - WalletScreen showing current TRY_COIN balance (formatted with locale)
  - List of active cashback plans for the user
  - Per plan: cumulative monthly coin earnings chart (last 12 months + projection of next 12; perpetual)
  - Total earned to date, total scheduled, plan freeze badge ("Plan dondurulmuş")
  - Pull to refresh

API:
  GET /v1/wallet/balance?currency=TRY_COIN
  GET /v1/cashback/plans?status=active
  GET /v1/cashback/plans/:id/payments

State management: Riverpod 2 AsyncNotifier per resource.

Atomic widgets used:
  - CoinBalancePill (atom)
  - PlanCard (molecule)
  - MonthDot (atom)
  - PlanTimelineRow (molecule)
  - PlanList (organism)

Empty state: "Henüz aktif cashback planınız yok. İlk siparişiniz teslim edildiğinde plan oluşur."

Report: widget tree, sample screen render in golden tests, API request log.
```

---

## Prompt 4.4 — Seller Panel Web View (Trendyol Comparison)

**Phase & Goal:** Phase 4. Web view component (or web app deployed under seller.moproshop.com) showing the seller transparency table.

**Copy-Paste Prompt:**

```
Implement /seller-panel (separate Vue/React app deployed under seller.moproshop.com).

Sayfa: Sipariş Detay
  - GET /api/v1/seller/orders/:id/breakdown
  - Render rows: variant | qty | brüt | komisyon (% + ₺) | KDV | hizmet bedeli (0 ₺) | net
  - Total row at the bottom
  - Side panel: Trendyol vs Hepsiburada vs Mopro karşılaştırma (rendered from same data; service fee fields show 0 ₺ for Mopro, ~5/7 ₺ for competitors per PRD § 2.2.4)
  - Footer: "Ödeme tarihi: Sipariş teslim + 3 iş günü = <DD.MM.YYYY>" (read from /v1/payouts/:order_id endpoint)

Sayfa: Aylık Komisyon Faturası
  - Lists all paid orders for the month
  - Sum row: brüt, komisyon, KDV, net
  - Download as PDF (KDV-dahil komisyon faturası, Mopro'nun keserek satıcıya verdiği)

Login: SSO with the satıcı hesabı (existing identity service).

Report: screenshot wireframe description, sample API response, UI text strings.
```

---

## Prompt 4.5 — Mobil Uygulamanın 35 Ekranı — v7 KAPSAMLI SPESİFİKASYON

**Phase & Goal:** Phase 4. Mobil uygulamanın TÜM ekranları için spec. Her ekran için: amaç, bileşenler, navigation, API çağrıları, state yönetimi.

**Copy-Paste Prompt:**

```
READ FIRST: /mobile/lib/* skeleton (Prompt 4.1 sonucu), DEVELOPMENT.md § 15 (i18n).

35 ekranı tek tek implement et. Her ekran kendi feature klasörü altında, atomic
design (atom/molecule/organism) yapısıyla. Tüm metinler context.tr() ile.

Her ekran için bu spec'i uygula. Ekran ekran:

═══ AUTH ═══
1. SplashScreen (/lib/features/auth/splash_screen.dart)
   - 1.5s logo animasyon, sonra route: token varsa Home, yoksa Onboarding.
   - Init: warm-up Riverpod providers (locale, theme, deepLink).

2. OnboardingScreen — 3 sayfalık swipe carousel
   - Sayfa 1: "Komisyon faizi sana iade — süresiz" + illüstrasyon
   - Sayfa 2: "Trendyol kalitesi, Mopro şeffaflığı"
   - Sayfa 3: "Hemen başla" → "Telefon ile Giriş" CTA
   - SharedPrefs flag: shown_onboarding=true

3. PhoneEntryScreen
   - +90 country code prefix (kilitli; Phase 1)
   - Telefon input, format mask "5XX XXX XX XX"
   - "Devam" CTA → POST /v1/auth/otp/request
   - Loading state, hata durumunda toast

4. OtpVerifyScreen
   - 6 haneli OTP, auto-advance, paste destekli
   - 60s sayaç + "Tekrar gönder" disabled until 0
   - POST /v1/auth/otp/verify → JWT + refresh token
   - İlk girişse: route ProfileSetupScreen, değilse HomeScreen

5. ProfileSetupScreen — Sadece ilk girişte
   - Ad, soyad, doğum tarihi (opt), e-posta (opt)
   - "Tamamla" → PUT /v1/me + route Home

═══ DISCOVERY ═══
6. HomeScreen (/lib/features/home/)
   - Top bar: arama icon, sepet icon (badge), bildirim icon
   - Banner carousel (3-5, GET /v1/banners?placement=home)
   - "Bugün Cashback Şampiyonları" yatay scroll (en yüksek aylık coin/ürün)
   - Kategori chip listesi (top 12)
   - "Sana Özel" GET /v1/recommendations
   - "Yeni Gelenler" GET /v1/products?sort=newest
   - Pull-to-refresh
   - Bottom nav: Anasayfa | Kategori | Sepet | Cüzdan | Profil

7. CategoryListScreen
   - 42 kategori grid (icon + isim)
   - GET /v1/categories
   - Tap → CategoryProductsScreen

8. CategoryProductsScreen
   - Filter (fiyat aralığı, marka, renk, beden, indirimli, hızlı kargo)
   - Sort (önerilen, en yeni, fiyat artan/azalan, en çok satan)
   - Sonsuz scroll, GET /v1/products?category_id=X&page=N
   - Her kart: foto, başlık, fiyat, "Aylık X.XX coin/ay" rozeti, sepete ekle butonu

9. SearchScreen
   - Arama bar (autofocus on tap from home)
   - Geçmiş aramalar (lokal storage)
   - Trend aramalar (GET /v1/search/trending)
   - Live suggestions: GET /v1/search/suggest?q=X (debounce 250ms)
   - Sonuç sayfası: aynı CategoryProductsScreen widget'ı

10. ProductDetailScreen — kritik
   - Foto galeri (swipe + zoom)
   - Başlık, fiyat (büyük), satıcı adı (tap → seller profili)
   - "Bu üründen aylık X.XX Mopro Coin kazanırsın — SÜRESİZ" rozet (kalın, ACCENT renk)
   - Cashback hesaplayıcı kartı: "5 yıl boyunca toplam Y.YY coin kazanırsın (=Y₺ değer)"
   - Variant seçici (renk, beden) — out-of-stock disabled
   - Adet stepper
   - "Sepete Ekle" + "Hemen Al" sticky bottom
   - Açıklama, özellikler, kargo süresi, iade koşulları (collapsible)
   - "Müşteri Yorumları" (puanlar + filtreli liste)
   - "Beraber Alınanlar" (yatay scroll)
   - GET /v1/products/:id

═══ CART & CHECKOUT ═══
11. CartScreen
   - Sepetteki tüm varyant satırları
   - Her satır: foto, başlık, varyant, qty stepper, fiyat, kaldır
   - Sticky bottom: ara toplam, "X coin/ay kazanacaksın" özet, "Devam Et" CTA
   - Boş sepet state'i + CTA "Alışverişe Başla"
   - GET /v1/cart, PATCH /v1/cart/items/:id, DELETE /v1/cart/items/:id

12. AddressSelectScreen (checkout 1/4)
   - Kayıtlı adres listesi
   - "Yeni adres ekle" CTA → AddressFormScreen
   - GET /v1/addresses

13. AddressFormScreen
   - Ad-soyad, telefon, il (dropdown 81 il), ilçe (dependent dropdown), mahalle, açık adres, posta kodu
   - "Kaydet" → POST /v1/addresses

14. CargoSelectScreen (checkout 2/4)
   - Calculated rates from all carriers (CalculateRate API)
   - Her kart: kargo logo, isim, tahmini teslim, ücret
   - "Bedava kargo" rozeti (eşik üstü)
   - Default seçili: en ucuz veya satıcı default

15. PaymentMethodScreen (checkout 3/4)
   - "Kredi/Banka Kartı" tab (3DS akışı)
   - "Mopro Coin Bakiye" tab (varsa kullan)
   - "Kapıda Ödeme" (gelecek; v1 disabled)
   - Kart formu: kart numarası, isim, son kullanma, CVV (PSP HPP üzerinden render edilir, biz form'u host ETMEYİZ)
   - "Bilgilerimi sakla" toggle (PSP-side tokenization)

16. CheckoutSummaryScreen (checkout 4/4)
   - Adres özeti
   - Kargo özeti
   - Ürün listesi
   - Ödeme yöntemi
   - Ara toplam, kargo, KDV, TOPLAM
   - "Bu siparişten aylık X.XX Mopro Coin kazanacaksın — SÜRESİZ" highlight
   - KVKK + satış sözleşmesi onay checkbox'ları (zorunlu)
   - "Siparişi Tamamla" CTA → POST /v1/orders/checkout (Idempotency-Key header)
   - Sonra 3DS HTML render veya direkt OrderConfirmedScreen

17. ThreeDSWebViewScreen
   - PSP hosted 3DS sayfası (WebView)
   - returnURL'e geri dönünce yapılan POST'a göre Confirmed/Failed

18. OrderConfirmedScreen
   - "Siparişin alındı! 🎉" (NOT: emoji sadece kullanıcı isterse — bu spec'te illüstrasyon kullan)
   - Sipariş numarası
   - "Sipariş tamamlandığında her ay X.XX Mopro Coin kazanmaya başlayacaksın"
   - "Siparişlerime Git" + "Alışverişe Devam" CTA

═══ ORDER MANAGEMENT ═══
19. OrderListScreen
   - Sekmeler: Aktif | Tamamlanan | İptal/İade
   - Her kart: sipariş no, tarih, durum (renkli badge), ürün adedi, toplam, "Detay" tap
   - GET /v1/orders?status=X&page=N

20. OrderDetailScreen
   - Sipariş no, tarih, durum timeline (görsel: Sipariş alındı → Hazırlanıyor → Kargoda → Teslim edildi)
   - Ürün listesi (tap → ProductDetail)
   - Adres + kargo bilgisi + tracking link
   - Ödeme özeti
   - Cashback durumu: "Kazanmaya başlama tarihi: <DD.MM.YYYY>" veya "Aylık <X.XX> coin alıyorsun"
   - "Faturayı Görüntüle" (e-arşiv PDF link)
   - Aksiyon butonları: "İade Talebi" (delivered+14 gün içinde), "Destek Aç"

21. ReturnRequestScreen
   - İade edilecek ürünleri seç (qty)
   - İade nedeni (dropdown: hatalı ürün, beğenmedim, hasarlı, diğer)
   - Açıklama (text)
   - Foto yükle (max 3)
   - "İade Başlat" → POST /v1/orders/:id/returns
   - Sonra: "İade kargo kodu yakında WhatsApp/SMS ile gelecek"

22. ReturnTrackScreen
   - İade durumu timeline (Talep alındı → Kargoda → Mopro deposu → Onaylandı/Reddedildi → Refund completed)
   - Refund detayı: ne kadar geri verildi (TL + coin clawback özet)

═══ WALLET (CASHBACK) ═══
23. WalletScreen (Bottom nav)
   - Bakiye kartı: büyük "TRY_COIN: X.XX" + "= ₺X.XX" eşdeğeri
   - "TL'ye Çevir" CTA (lisans aktif değilse: "Yakında" disabled)
   - Bu Ay Kazanılan: Y.YY coin
   - Aktif planlar sayısı: "12 aktif plan, aylık toplam Z.ZZ coin"
   - "Tüm Planlar" tap → CashbackPlansScreen
   - Aylık coin akış grafiği (son 12 ay + 12 ay projeksiyon)
   - GET /v1/wallet/balance, GET /v1/cashback/plans

24. CashbackPlansScreen
   - Aktif plan listesi
   - Her kart: ürün foto, başlık, "X.XX coin/ay süresiz", sipariş tarihi, "Detay"
   - Boş state: "Henüz cashback planın yok. İlk siparişin teslim edildiğinde başlar."

25. CashbackPlanDetailScreen
   - Ürün özet
   - "Aylık coin: X.XX TRY_COIN"
   - "Plan başlangıç tarihi: DD.MM.YYYY"
   - "Bugüne kadar toplam: Y.YY coin (Z ay × X.XX)"
   - "Plan dondurulmuş — TL devalüasyonundan etkilenmez"
   - Ödeme geçmişi tablosu (ay, miktar, durum)

26. CoinToFiatScreen — Phase 7+
   - Çevrim miktarı slider/input
   - Anlık kur + komisyon
   - "Banka hesabıma gönder" → IBAN seç (kayıtlı listeden)
   - Step-up auth (biometric/SMS OTP)
   - Onay → POST /v1/wallet/convert

═══ PROFILE ═══
27. ProfileScreen (bottom nav)
   - User avatar + ad + telefon (maskeli)
   - Liste:
     - Adreslerim
     - Ödeme Yöntemlerim
     - Bildirim Tercihleri
     - Dil & Lokalizasyon
     - KVKK & Veri
     - Yardım & Destek
     - Hakkında / Sürüm
     - Çıkış Yap
   - "Hesabımı Sil" (en altta, kırmızı; KVKK gereği zorunlu)

28. NotificationPrefsScreen
   - Push: Cashback ödemeleri, Sipariş güncellemeleri, Promosyonlar, Yeni ürünler
   - SMS: Sipariş onay (zorunlu), Şifre sıfırlama (zorunlu), Kampanya (opt)
   - E-posta: Aynı kategoriler

29. AddressBookScreen
   - Kayıtlı adres listesi (default işaretli)
   - "Yeni adres", swipe-to-delete

30. SavedPaymentMethodsScreen
   - PSP-tokenize edilmiş kart listesi (last4 + brand)
   - "Yeni kart ekle" (PSP HPP)
   - Sil

31. AccountDeletionScreen
   - Uyarı: "Tüm aktif cashback planların iptal olur, kazanılmamış coin'in kaybolur"
   - Sebep dropdown (zorunlu)
   - Şifre/OTP onay
   - "Hesabımı Kalıcı Olarak Sil" → POST /v1/me/delete (GDPR/KVKK 30 gün geri alınabilir)

═══ SUPPORT ═══
32. SupportHomeScreen
   - "AI Asistana Sor" prominent CTA → SupportChatScreen
   - SSS (kategorize): Cashback nedir? Coin'i nasıl harcarım? İade nasıl yapılır?
   - "Talep Aç" CTA → SupportTicketFormScreen
   - "Geçmiş Taleplerim"

33. SupportChatScreen
   - LLM-destekli chat (jobs-svc.support üzerinden)
   - Bot intent → cevap veya "İnsana bağlıyorum" → ticket oluştur
   - Mesaj geçmişi tutulur

34. SupportTicketFormScreen
   - Konu dropdown, açıklama, ekler (foto)
   - "Gönder" → POST /v1/support/tickets

35. SupportTicketListScreen
   - Açık/Kapalı taleplerin listesi
   - Tap → mesaj thread'i

═══ COMMON ═══
36. NotificationCenterScreen (top bar icon)
   - Bildirim listesi (cashback ödendi, sipariş güncel, promosyon)
   - Read/unread state, tap → ilgili sayfaya deeplink

═══ SHARED PATTERNS ═══
- Loading: skeleton placeholder (NOT spinner)
- Error: tek tip ErrorView widget (illüstrasyon + mesaj + retry CTA)
- Empty state: tek tip EmptyView widget (illüstrasyon + mesaj + primary CTA)
- Bottom sheet for filters/sort
- Snackbar (toast) for non-blocking feedback
- Dialog for destructive confirms (iade, hesap sil)

═══ DESIGN TOKENS ═══
- Primary: #1F4E79 (Mopro Mavi)
- Accent: #2E75B6
- Success/Coin: #375623
- Warning: #C65911
- Error: #9B2226
- Background: #FFFFFF / #121212 (dark)
- Font family: Inter (Latin), Noto Sans Turkish

═══ TESTS ═══
- Golden tests for each screen (light + dark mode)
- Widget tests for cart math, cashback math, address form validation
- Integration test (e2e): onboarding → ürün ekle → checkout → siparişi gör

Report:
- 36 screen files compiled
- Golden test count
- Sample run on iOS simulator + Android emulator (screenshot batches)
```

**Verification / Done Criteria:**
- [ ] 36 screen widgets compiled.
- [ ] All user-facing strings via context.tr (no hardcoded TR/EN strings in widget code).
- [ ] Golden tests cover happy path of every screen.
- [ ] Bottom navigation 5 tabs: Anasayfa, Kategori, Sepet, Cüzdan, Profil.
- [ ] Cashback preview text appears in: ProductDetail, Checkout, OrderConfirmed.
- [ ] Account deletion flow respects KVKK 30-day reversibility window.

---

# PHASE 5 — Observability & Hardening

## Prompt 5.1 — slog + trace_id + market label on Every HTTP Handler

**Phase & Goal:** Phase 5. Structured JSON logs with trace_id and market label everywhere.

**Copy-Paste Prompt:**

```
READ FIRST: INFRASTRUCTURE.md § 9.1.

Implement /pkg/logger/slog.go that wraps log/slog and:
  - Emits JSON.
  - Always includes time, level, service, module, market, currency (if set in ctx), trace_id, span_id, msg.
  - PII is NEVER allowed; provide a sanitize helper that hashes PII fields.

Implement /pkg/httpx/middleware.go:
  TraceAndLog middleware that:
    - Extracts X-Trace-Id from request (or generates one)
    - Stores in ctx
    - Logs request start + complete (with status, duration)
  LocaleResolver middleware:
    - Reads Accept-Language; resolves to user's stored locale (or default)
    - Stores in ctx
  IdempotencyMiddleware:
    - For POST/PUT/PATCH: requires X-Idempotency-Key header; stores in ctx
    - On duplicate (idempotency table): returns cached prior response

Wire all three binaries to use these middlewares on all HTTP routes.

Report: example log line, middleware code, ctx flow.
```

---

## Prompt 5.2 — disk-watch.sh with Panic Mode at 92%

**Phase & Goal:** Phase 5. The disk panic script per DISASTER_RECOVERY.md § 2.

**Copy-Paste Prompt:**

```
Implement /opt/mopro/scripts/disk-watch.sh exactly as in DISASTER_RECOVERY.md § 2.3.
Wire as cron */5 * * * * deploy /opt/mopro/scripts/disk-watch.sh.
Add /opt/mopro/scripts/disk-hygiene.sh per § 2.5.

Test by filling disk to 90% (sparse file) → verify Slack alert; to 93% → verify Postgres goes read-only.
Restore by deleting the sparse file → verify ALTER SYSTEM SET default_transaction_read_only = off recovery procedure.

Verify cashback monthly cron AND seller payout daily cron both fail GRACEFULLY during read-only window (rollback, payments stay 'scheduled').

Report: script, test logs.
```

---

## Prompt 5.3 — Backup Pipeline + Weekly Restore Drill

**Phase & Goal:** Phase 5. Continuous WAL backup of both Postgres clusters + daily full dump + weekly restore verification.

**Copy-Paste Prompt:**

```
READ FIRST: DISASTER_RECOVERY.md § 6.

Implement:
  /opt/mopro/scripts/backup.sh — daily full dump of both Postgres clusters via pg_dumpall; restic push to B2.
  WAL archive_command in postgresql.conf for both clusters → wal-push to B2.
  /opt/mopro/scripts/restore-drill.sh — weekly Sunday 04:00 per § 6.3.

Cron:
  0 3 * * *  deploy /opt/mopro/scripts/backup.sh
  0 4 * * 0  deploy /opt/mopro/scripts/restore-drill.sh

Healthchecks: HEALTHCHECK_BACKUP_UUID + HEALTHCHECK_RESTORE_UUID.

Verify: trigger restore-drill manually → fresh Postgres receives the dump → SELECT count(*) FROM catalog_schema.products > 0 → cleanup.

Report: scripts, restore-drill log, healthcheck pings.
```

---

## Prompt 5.4 — TR e-Fatura / e-Arşiv / GİB Entegrasyonu — v7 NEW

**Phase & Goal:** Phase 5. GİB üzerinden Foriba (veya alternatif) Bulut e-Fatura sağlayıcısı ile e-fatura kesme ve KDV beyanı altyapısı. Mopro her ay satıcılara komisyon faturası keser; Phase 5+ own-seller modunda alıcılara e-arşiv keser.

**Copy-Paste Prompt:**

```
READ FIRST: ARCHITECTURE.md § 8.7, DATA_DICTIONARY.md § 11.

Implement /internal/einvoice/ inside jobs-svc (heavy I/O + XML processing
shouldn't block core-svc). Module owns:
  /internal/einvoice/api.go        ← Service interface
  /internal/einvoice/service.go    ← orchestration
  /internal/einvoice/foriba/       ← active provider adapter
  /internal/einvoice/provider.go   ← adapter interface (kolay swap için)
  /internal/einvoice/templates/    ← UBL-TR XML templates (Go templates)
  /internal/einvoice/repository.go ← einvoice_schema repo
  /internal/einvoice/worker.go     ← async submitter cron

Service interface:
  IssueCommissionInvoice(ctx, orderID, sellerID, amountMinor, kdvMinor) → (InvoiceRef, error)
  IssueMonthlySummary(ctx, sellerID, periodYYYYMM) → (InvoiceRef, error)
  IssueSaleInvoice(ctx, orderID, buyerInfo, lineItems[]) → (InvoiceRef, error)     // Phase 5+
  IssueCreditNote(ctx, originalInvoiceID, reason, amountMinor) → (InvoiceRef, error)
  CancelInvoice(ctx, invoiceID, reason) → error                                     // 8 gün içinde
  GetInvoiceByOrderID(ctx, orderID, type) → (Invoice, error)
  HandleProviderWebhook(ctx, providerName, body) → error                            // Foriba → bize

— FORIBA ADAPTER —
Sandbox: https://earsivportaltest.foriba.com (login: kurumsal hesap)
Prod:    https://earsivportal.foriba.com

Auth: POST /auth/login { username, password } → JWT (24h TTL).
  Cache token in Redis: einvoice:foriba:token; refresh on 401.

Endpoints:
  POST /einvoice/send
    Headers: Authorization: Bearer <jwt>
    Body: { invoice_xml: base64(UBL-TR XML), invoice_type: "TEMELFATURA"|"TICARIFATURA",
            recipient: { vkn, title, address } }
    Response: { foriba_id, ettn, status: "QUEUED" }
  POST /earsiv/send
    Body: { invoice_xml, recipient: { tckn, email, name, address } }
  GET  /invoice/status/{foriba_id}
    Response: { status, gib_response, errors[]? }
  POST /einvoice/cancel/{foriba_id}
    Body: { reason }   // only allowed if 8 days have not passed AND GİB not yet ACCEPTED
  POST /webhook/register
    Body: { url: "https://api.moproshop.com/v1/einvoice/webhook/foriba", events: ["sent","delivered","rejected","cancelled"] }

Webhook receiver (in core-svc or jobs-svc):
  POST /v1/einvoice/webhook/foriba
    Verify X-Foriba-Signature = hmacSha256(rawBody, FORIBA_WEBHOOK_SECRET)
    Update einvoice_schema.invoices.status accordingly.

Sandbox creds env names:
  FORIBA_USERNAME, FORIBA_PASSWORD, FORIBA_WEBHOOK_SECRET, FORIBA_VKN

— UBL-TR XML TEMPLATE —
Template at /internal/einvoice/templates/commission_invoice.xml:
  Use TR-specific UBL-TR 2.1 schema.
  Required fields:
    - cbc:UBLVersionID, cbc:CustomizationID="TR1.2"
    - cbc:ProfileID="TEMELFATURA" or "TICARIFATURA"
    - cbc:ID = invoice_number (Mopro üretir; sequence'den)
    - cbc:UUID = uuidv4
    - cbc:IssueDate, cbc:IssueTime
    - cbc:InvoiceTypeCode = "SATIS" | "IADE"
    - cac:AccountingSupplierParty (Mopro VKN, ünvan, adres)
    - cac:AccountingCustomerParty (satıcı VKN, ünvan, adres)
    - cac:InvoiceLine (her satır: ürün/hizmet, miktar, birim fiyat, vergi)
    - cac:TaxTotal (KDV %20 hesabı)
    - cac:LegalMonetaryTotal (toplam)
  Validate: xmllint against UBL-TR XSD before submission.

— SEQUENCE NUMBER GENERATION —
Format: <Prefix><YY><sequence10>
  Prefix: 'MPS' (Mopro Shop) for e-fatura; 'MPA' for e-arşiv.
  Year: 2-digit (26, 27, ...).
  Sequence: per year + type, 10-digit zero-padded, atomically incremented via:
    UPDATE einvoice_schema.invoice_sequences
       SET next_number = next_number + 1
       WHERE year = $1 AND invoice_kind = $2
       RETURNING next_number;
  Example: "MPS260000000123"
  TR mevzuat: sıralı VE atlamasız; bir fatura iptal edilirse sıra atlanmaz, ters fatura kesilir.

— WORKER: einvoice-submitter (jobs-svc cron) —
Every 5 minutes:
  SELECT * FROM einvoice_schema.invoices WHERE status='pending' ORDER BY created_at LIMIT 100
  For each:
    1. Render XML from template + invoice data.
    2. Submit to Foriba: POST /einvoice/send.
    3. On success: UPDATE status='queued', store foriba_invoice_id + ettn.
    4. On failure: UPDATE status with last_error; retry up to 5 times with exponential backoff.
       Beyond 5: status='rejected', alert on-call (SEV2).
  Insert audit row in invoice_history.

— ORDER-TO-INVOICE FLOW —
Triggered by ecom.order.delivered.v1 (yes, AGAIN — third consumer group):
  jobs-svc.einvoice subscribes to ecom.order.delivered.v1
  For each delivered order:
    1. Per seller in order_items: aggregate commission_amount_minor + kdv_amount_minor.
    2. Create einvoice_schema.invoices row:
       type='commission', seller_id, amount_minor=sum(commission), kdv_minor=sum(kdv),
       invoice_kind='e_fatura' (satıcı VKN'li mükellef ise) veya 'e_arsiv' (değilse),
       status='pending', idempotency='einvoice:order_<id>:commission'.
    3. Worker picks up and submits.

— MONTHLY SUMMARY INVOICE —
Cron: 1st of each month 03:00 UTC.
  For each seller:
    Aggregate all paid commissions for the previous month.
    Issue ONE summary e-fatura instead of per-order (if seller prefers; configurable per seller).
    type='monthly_summary'.

— LEDGER INTEGRATION —
Each issued commission invoice writes a ledger move (fin-svc.commission receives an event):
  D liability:kdv_payable:TRY   amount=kdv_minor    (KDV devlete borç)
  C equity:retained_commission:TRY amount=kdv_minor (Mopro'nun komisyon gelirinden ayrılan KDV payı)
This already happens inside fin-svc at order capture time; we just CROSS-REFERENCE
the einvoice number into the wallet_schema.transactions.reference for audit.

— KDV BEYAN CRON —
Cron: 25th of each month 08:00 UTC (1 gün önce hazırla, 26'sında imzala/gönder).
  Compute for previous month (period_yyyymm = current - 1):
    total_invoiced = SUM(einvoice_schema.invoices.amount_minor WHERE status IN ('sent','delivered') AND invoice_date IN month)
    total_kdv_collected = SUM(kdv_minor) similarly
    total_kdv_paid = SUM(KDV from Mopro's expense invoices — separate ingestion)
    net_due = total_kdv_collected - total_kdv_paid
  INSERT INTO einvoice_schema.kdv_declarations.
  Send notification to muhasebe@moproshop.com with the summary.
  Muhasebeci/CFO Foriba portalı üzerinden GİB'e gönderir (manual final step).

— TESTS —
1. UBL-TR XML validation against XSD (using xmllint or Go xsd lib).
2. Sequence: 1000 concurrent IssueCommissionInvoice calls → no duplicate numbers, no gaps.
3. Worker idempotency: re-process same pending row → no duplicate Foriba submission.
4. Webhook signature: tamper with body → reject.
5. Cancellation 8-day window: after 8 days, refuse cancel; suggest credit note.
6. End-to-end: simulate delivered order → invoice issued + delivered → ledger references match.

— SECURITY —
- Mopro VKN is non-secret; recipient VKN/TCKN treated as PII (encrypt via crypto.EncryptPII).
- Invoice XMLs stored in B2 with seller_id-prefixed key for fine-grained access.
- 10-year retention (TR mevzuat zorunluluğu).
- KEP adresi: ptt@mopro.kep.tr veya benzeri (Phase 0'da alın).

Report: module structure, sandbox submission example, sequence number test,
KDV beyanı dummy run.
```

**Verification / Done Criteria:**
- [ ] All einvoice_schema tables created via migration.
- [ ] Foriba sandbox: 10 commission invoices submitted, ETTN'leri alındı.
- [ ] UBL-TR XML XSD validation passes.
- [ ] Sequence numbers atomic, no duplicates under 1000 concurrent test.
- [ ] Cancel-after-8-days returns proper error + credit-note suggestion.
- [ ] KDV declaration cron runs end-to-end, summary email sent.
- [ ] Webhook signature validation enforced.

---

# PHASE 6 — Pre-Launch Validation

## Prompt 6.1 — k6 Load Testing Harness

**Phase & Goal:** Phase 6. Load testing for 30K users/hour target with cashback + seller payout flow stress.

**Copy-Paste Prompt:**

```
Create /tests/load/k6/ with scenarios:
  - browse.js: anonymous + authenticated browsing (catalog, search) — 100 RPS sustained.
  - checkout.js: end-to-end checkout including PSP sandbox — 5 RPS sustained, peaks of 20 RPS.
  - delivered.js: simulate kargo webhooks delivering orders → cashback engine + seller payout engine fire.
  - cashback-cron.js: simulate 10K active plans with payments due → run cashback cron, measure duration < 30s.
  - seller-payout-cron.js: simulate 1000 due payouts → run cron, measure duration < 5min, PSP API mocked.

Pass criteria:
  - p95 < 300ms on browse.
  - p95 < 800ms on checkout.
  - cashback cron < 30s for 10K plans.
  - seller payout cron < 5min for 1000 payouts.
  - 0 errors on the cron paths.

Run on a clone of production VDS (not production).
Report: results JSON, p95 graphs, GC/CPU saturation chart.
```

---

## Prompt 6.2 — Final Launch Readiness Script

**Phase & Goal:** Phase 6. A pre-launch checklist script that verifies every invariant.

**Copy-Paste Prompt:**

```
Implement /scripts/launch-readiness.sh that runs and prints PASS/FAIL for each:
  - All containers healthy (docker compose ps)
  - mopro ledger reconcile --dry-run shows 0 deltas per currency
  - mopro cashback obligation-check matches
  - mopro payout obligation-check matches
  - 42 commission rules seeded for TR
  - 50+ business calendar entries seeded for TR (2026-2030)
  - Backup last 24h ping received in healthchecks.io
  - Restore drill last 7 days ping received
  - Disk usage < 60%
  - All Postgres extensions installed
  - PSP webhook signature validated end-to-end with sandbox
  - Caddy TLS valid (cert expiry > 30 days)
  - JWT signing key present + > 32 bytes
  - PII KEK present + 32 bytes
  - i18n translations present for tr-TR and en-US (count of keys matches)
  - Cashback monthly cron configured + healthcheck UUID set
  - Seller payout daily cron configured + healthcheck UUID set
  - Outbox lag < 10s
  - Any DLQ messages? FAIL if > 0

If ANY fails: launch is BLOCKED.

Report: script, sample output, blocked vs go criteria.
```

---

# PHASE 7 — Coin License Activation (Future)

## Prompt 7.1 — Activate Coin → Fiat Conversion

**Phase & Goal:** Phase 7. After Dubai VARA or AB EMI license is activated, enable the coin → fiat conversion flow.

**Copy-Paste Prompt:**

```
READ FIRST: DISASTER_RECOVERY.md § 11, LEDGER_GUIDE.md § 4.2.

Implement /internal/treasury/conversion.go:
  Service:
    QuoteConversion(ctx, userID, amountCoinMinor, targetCurrency) (Quote, error)
    ExecuteConversion(ctx, userID, quoteID, idempotencyKey) (Conversion, error)

  Quote structure: { CoinAmountMinor, FiatAmountMinor, Rate, ExpiresAt }
  Quote validity: 60 seconds.
  Rate source: Treasury internal mid-rate ± 1% spread.

  Execute logic (TWO ledger transactions linked by fx_pair_id):
    Transaction A (TRY_COIN-only):
      D liability:wallet:user_<id>:TRY_COIN  amount=coinAmountMinor
      C asset:fx_pool:TRY_COIN              amount=coinAmountMinor

    Transaction B (TRY-only):
      D asset:fx_pool:TRY              amount=fiatAmountMinor
      C asset:bank:outbound_pending:TRY amount=fiatAmountMinor

  PSP outbound transfer (Sipay/Craftgate marketplace API, same adapter as seller payout)
  initiated to user's verified bank account.

Feature flag: FEATURE_COIN_TO_FIAT_CONVERSION=true (off by default).
Step-up auth: require biometric/OTP per CLAUDE.md § 6.

Property test: For random (coinAmount, rate, spread), the two ledger transactions sum-balance independently per currency.

Add /v1/wallet/convert endpoint in fin-svc (admin-only until launch day, then public).

Report: code, property test output, end-to-end test with mock PSP.
```

**Verification / Done Criteria:**
- [ ] Both transactions commit independently or both roll back together (saga).
- [ ] fx_pair_id links them in audit log.
- [ ] User cannot convert before step-up auth.
- [ ] Existing cashback plans unaffected by license activation.

---

# Appendix A — Property Test Skeletons

(Refer to DEVELOPMENT.md § 7.2 for full ledger and cashback property tests.)

# Appendix B — Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Hardcoded fixed-term plan or finite total in v6 | Plan model conflict | Use perpetual model — only `monthly_amount_minor` + `start_date` |
| Hardcoded reference rate other than 5000 bps | v6 model violation | Use `cashback.ReferenceInterestRateBpsConst` (=5000 = %50) |
| Calendar-day delay | unlock_at off by weekends | Use `pkg/timex.AddBusinessDays(date, 3, calendar)` |
| Recompute commission at plan time | Diverges from order snapshot | Read `order_items[i].commission_amount_minor` from event payload |
| Forgetting one of the two consumer groups | Cashback fires but no seller payout (or vice versa) | Both groups subscribed to the same `ecom.order.delivered.v1` |
| Mutating plan or payout core fields | Trigger raises | Use reversal pattern from LEDGER_GUIDE § 7.4 / § 8 |
| Mixed-currency in one ledger transaction | Trigger raises | Split into TWO transactions linked by `fx_pair_id` |

---

**End of PROMPTS.md.** This is the canonical recipe book; deviations require an ADR in `/docs/adr/`.

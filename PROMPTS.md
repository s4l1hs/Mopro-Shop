# PROMPTS.md — Master Prompt Library

This file is the **official anthology of commands** an operator gives to Claude Code (or any autonomous coding agent) to build Mopro Shop from an empty repository to a launched production system. Every prompt is copy-paste-ready, restrictive, and faithful to PRD v3.2.

## How to Use

1. Pick the phase you are in (0 through 6).
2. Find the matching prompt by goal.
3. Copy the **Copy-Paste Prompt** block verbatim and feed it to the agent.
4. After the agent completes, run the **Verification / Done Criteria** checklist. Do not advance to the next prompt until every item passes.

## Conventions

- Every prompt opens with `READ FIRST: CLAUDE.md, ARCHITECTURE.md, DATA_DICTIONARY.md, LEDGER_GUIDE.md, INFRASTRUCTURE.md.` This forces the agent to load context.
- `ghcr.io/mopro/<binary>` is the canonical image namespace.
- Module path is `github.com/mopro/platform`.
- All shell snippets are POSIX `bash`; the host is Ubuntu 22.04 / Debian 12.
- All Go code is `go 1.22+`; all Postgres SQL targets PostgreSQL 16; all Redis is 7.x.
- The single VDS is 6 vCPU / 24 GB RAM / 120 GB disk.

---

# PHASE 0 — Infrastructure & Skeleton

The goal of Phase 0 is to produce an empty but **buildable, runnable, tested** monorepo with the three binaries, the two Postgres clusters with all rules and triggers in place, the Redis Streams event bus, and the Docker Compose stack.

## Prompt 0.1 — Initialize Monorepo Skeleton

**Phase & Goal:** Phase 0. Create the repository directory layout, Go modules, linter rules, Makefile, and base configuration so that `make verify` runs on an empty project.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: CLAUDE.md, ARCHITECTURE.md, DATA_DICTIONARY.md, INFRASTRUCTURE.md, DEVELOPMENT.md.

Create the initial monorepo skeleton for Mopro Shop. Do not write business logic; only create the structure, config, and stubs that compile.

CREATE THESE PATHS (exact list — do not add or remove):

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
/pkg/httpx/
/pkg/dbx/
/pkg/timex/

/migrations/ecom/
/migrations/ledger/

/build/Dockerfile
/build/Dockerfile.dockerignore

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

/.golangci.yml
/.gitignore
/.dockerignore
/.editorconfig
/Makefile
/go.mod
/go.sum
/.env.example
/README.md

For each /internal/<name>/ directory, create five empty Go files: api.go (package <name>), service.go, repository.go, domain.go, errors.go. The api.go must declare:

  package <name>
  type Service interface{}
  type Repository interface{}

For each /cmd/<binary>/main.go, create a minimal `func main(){}` that loads env via os.Getenv("SVC_NAME"), prints "starting <binary>", and exits 0.

Use module path: github.com/mopro/platform

go.mod must require:
  - go 1.22
  - github.com/jackc/pgx/v5 (latest)
  - github.com/redis/go-redis/v9 (latest)
  - github.com/golang-migrate/migrate/v4 (latest)
  - github.com/leanovate/gopter (latest, for property tests)
  - go.opentelemetry.io/otel (latest)
  - go.opentelemetry.io/otel/sdk (latest)

.golangci.yml MUST configure depguard with the rules from DEVELOPMENT.md § 9 verbatim:
  - core-modules-no-fin: identity/catalog/cart/order/payment/seller/search cannot import internal/wallet, internal/commission, internal/treasury.
  - fin-no-ecom: wallet/commission/treasury cannot import internal/order, internal/payment.
  - modules-only-via-api: internal/order/** cannot import internal/catalog/repository or internal/catalog/service.

Makefile MUST define targets: verify, fmt, vet, test, lint, boundaries, build, build-core, build-fin, build-jobs, build-migrate, build-mopro, run-local, down-local. The verify target chains fmt vet test lint boundaries.

scripts/check-module-boundaries.sh MUST contain the script body from DEVELOPMENT.md § 10 verbatim.

scripts/install-hooks.sh installs a pre-push hook that runs `make verify` and aborts the push on failure.

.gitignore MUST include: .env*, !.env.example, /data/, /tmp/, /vendor/, *.test, coverage.out, .DS_Store, .idea/, .vscode/.

.dockerignore MUST exclude: .git/, .github/, *.md, docs/, deploy/, test/, testdata/, **/*.test, coverage.out, node_modules/, .local/.

.env.example MUST contain every variable from DEVELOPMENT.md § 3, with placeholder values like "REPLACE_ME". Never commit real secrets.

After creating the skeleton:
  1. Run `go mod tidy`.
  2. Run `make verify`. It MUST pass on the empty skeleton (no failing test, no lint error).
  3. Run `go build ./...`. It MUST succeed.

DO NOT add business logic. DO NOT introduce new dependencies beyond the list above. DO NOT add HTTP frameworks (chi/gin) yet — Phase 1 will choose. DO NOT add any code that connects to a real database.

Report at the end: list of files created, output of `make verify`, output of `go build ./...`.
```

**Verification / Done Criteria:**
- [ ] All listed paths exist exactly as specified.
- [ ] `go mod tidy` produces no errors.
- [ ] `go build ./...` succeeds.
- [ ] `make verify` exits 0 with all sub-targets green.
- [ ] `golangci-lint run` exits 0 (no warnings on empty modules).
- [ ] `git status` shows only intended files (no `.env`, `data/`, IDE folders).
- [ ] `scripts/check-module-boundaries.sh` exits 0.

---

## Prompt 0.2 — Create postgres-ecom Init Scripts (All Module Schemas)

**Phase & Goal:** Phase 0. Provision postgres-ecom with one schema per module, one role per module, and locked-down permissions. No tables yet — those are added in their phases.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: DATA_DICTIONARY.md (especially § 2.1 and § 2.3), CLAUDE.md § 5.

Create Postgres init scripts for postgres-ecom. The scripts run automatically when the container starts on an empty volume (Docker Postgres convention: /docker-entrypoint-initdb.d/*.sql executed in lexical order).

PATHS TO CREATE:

/deploy/postgres-ecom/init/00-extensions.sql
/deploy/postgres-ecom/init/10-roles.sql
/deploy/postgres-ecom/init/20-schemas.sql
/deploy/postgres-ecom/init/30-grants.sql

CONTENT REQUIREMENTS:

00-extensions.sql:
  - Enable pgcrypto, pg_stat_statements.

10-roles.sql:
  - Create one LOGIN ROLE per module:
    identity_user, catalog_user, cart_user, order_user, payment_user,
    seller_user, search_user, notification_user, support_user, media_user, sizefinder_user.
  - Each role's password is read from env via Postgres init: use placeholder bcrypt-style "REPLACE_BY_INIT" — passwords are set after container start by an outer wrapper; do not embed real passwords.
  - All roles: NOSUPERUSER, NOCREATEDB, NOCREATEROLE, INHERIT, LOGIN.

20-schemas.sql:
  - REVOKE ALL ON SCHEMA public FROM PUBLIC.
  - For each module, CREATE SCHEMA <module>_schema AUTHORIZATION <module>_user.
  - Eleven schemas total: identity_schema, catalog_schema, cart_schema, order_schema, payment_schema, seller_schema, search_schema, notification_schema, support_schema, media_schema, sizefinder_schema.

30-grants.sql:
  - For each <module>_user: GRANT USAGE ON SCHEMA <module>_schema, GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA <module>_schema, GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA <module>_schema, ALTER DEFAULT PRIVILEGES IN SCHEMA <module>_schema GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <module>_user.
  - NEVER grant cross-schema permissions. order_user must NOT have permission on catalog_schema.

Add a wrapper script /deploy/postgres-ecom/init/99-set-passwords.sh that reads passwords from env vars (IDENTITY_DB_PASSWORD, CATALOG_DB_PASSWORD, …) and runs ALTER USER for each role. Use this format so env-driven secrets never appear in SQL files.

Update /deploy/docker-compose.yml later (Prompt 0.5) to mount these init scripts into postgres-ecom under /docker-entrypoint-initdb.d/.

Add a /deploy/postgres-ecom/postgresql.conf with parameters from INFRASTRUCTURE.md § 16.2 (shared_buffers=2GB, effective_cache_size=6GB, work_mem=16MB, maintenance_work_mem=256MB, max_connections=100, wal_level=replica, max_wal_size=2GB, checkpoint_completion_target=0.9, log_min_duration_statement=200, autovacuum=on, autovacuum_max_workers=3, wal_keep_size=1GB, random_page_cost=1.1, effective_io_concurrency=200).

DO NOT add any tables. Tables are owned by their module migrations (Phase 1+).

Provide a one-time bootstrap doc at /deploy/postgres-ecom/README.md explaining the init order and how to rotate passwords.

Verify by:
  1. `docker compose up -d postgres-ecom` (after Prompt 0.5 wires it).
  2. `docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c "\dn"` — expect all eleven schemas.
  3. `docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c "\du"` — expect all module roles.
```

**Verification / Done Criteria:**
- [ ] All four init files exist with the prescribed content.
- [ ] Eleven schemas appear in `\dn` output.
- [ ] Eleven module roles appear in `\du`.
- [ ] No role has BYPASSRLS, CREATEDB, CREATEROLE, or SUPERUSER.
- [ ] Public schema permissions revoked from PUBLIC.
- [ ] postgresql.conf parameters match INFRASTRUCTURE.md exactly.
- [ ] Init scripts produce zero ERROR or WARNING in container logs on first run.

---

## Prompt 0.3 — Create postgres-ledger with D=C Trigger

**Phase & Goal:** Phase 0. Provision postgres-ledger with the wallet, commission, and treasury schemas, the append-only RULES, the DEFERRABLE INITIALLY DEFERRED double-entry trigger, and the outbox table. This is the financial heart of the system; getting it wrong here is catastrophic.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: LEDGER_GUIDE.md (entire file), CLAUDE.md § 4 and § 5, DATA_DICTIONARY.md § 2.2 and § 5.5.

Create Postgres init scripts for postgres-ledger. This is a SEPARATE CLUSTER from postgres-ecom; it lives on the mopro-fin-net Docker network and is reachable ONLY by fin-svc.

PATHS TO CREATE:

/deploy/postgres-ledger/init/00-extensions.sql
/deploy/postgres-ledger/init/10-roles.sql
/deploy/postgres-ledger/init/20-schemas.sql
/deploy/postgres-ledger/init/30-wallet-schema.sql
/deploy/postgres-ledger/init/31-wallet-trigger.sql
/deploy/postgres-ledger/init/32-wallet-rules.sql
/deploy/postgres-ledger/init/33-wallet-outbox.sql
/deploy/postgres-ledger/init/34-wallet-alerts.sql
/deploy/postgres-ledger/init/40-commission-schema.sql
/deploy/postgres-ledger/init/50-treasury-schema.sql
/deploy/postgres-ledger/init/60-grants.sql
/deploy/postgres-ledger/init/99-set-passwords.sh

CONTENT REQUIREMENTS:

00-extensions.sql:
  - CREATE EXTENSION IF NOT EXISTS pgcrypto;
  - CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

10-roles.sql:
  - LOGIN ROLE: wallet_user, commission_user, treasury_user.
  - All NOSUPERUSER, NOCREATEDB, NOCREATEROLE, LOGIN.

20-schemas.sql:
  - REVOKE ALL ON SCHEMA public FROM PUBLIC.
  - CREATE SCHEMA wallet_schema AUTHORIZATION wallet_user.
  - CREATE SCHEMA commission_schema AUTHORIZATION commission_user.
  - CREATE SCHEMA treasury_schema AUTHORIZATION treasury_user.

30-wallet-schema.sql (verbatim from LEDGER_GUIDE.md § 3):
  CREATE TABLE wallet_schema.accounts (
      id          BIGSERIAL PRIMARY KEY,
      type        TEXT NOT NULL,
      owner_type  TEXT,
      owner_id    BIGINT,
      currency    TEXT NOT NULL DEFAULT 'TRY_COIN',
      status      TEXT NOT NULL DEFAULT 'active',
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  );

  CREATE TABLE wallet_schema.transactions (
      id              BIGSERIAL PRIMARY KEY,
      type            TEXT NOT NULL,
      reference       TEXT,
      idempotency_key TEXT NOT NULL UNIQUE,
      status          TEXT NOT NULL DEFAULT 'posted',
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  );

  CREATE TABLE wallet_schema.ledger_entries (
      id              BIGSERIAL PRIMARY KEY,
      transaction_id  BIGINT NOT NULL REFERENCES wallet_schema.transactions(id),
      account_id      BIGINT NOT NULL REFERENCES wallet_schema.accounts(id),
      direction       CHAR(1) NOT NULL CHECK (direction IN ('D','C')),
      amount_minor    BIGINT NOT NULL CHECK (amount_minor > 0),
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  );

  CREATE INDEX ledger_entries_account_idx ON wallet_schema.ledger_entries(account_id);
  CREATE INDEX ledger_entries_txn_idx     ON wallet_schema.ledger_entries(transaction_id);

31-wallet-trigger.sql (verbatim from LEDGER_GUIDE.md § 4):
  CREATE OR REPLACE FUNCTION wallet_schema.enforce_double_entry()
  RETURNS TRIGGER AS $$
  DECLARE
      debit_total  BIGINT;
      credit_total BIGINT;
  BEGIN
      SELECT
          COALESCE(SUM(amount_minor) FILTER (WHERE direction='D'), 0),
          COALESCE(SUM(amount_minor) FILTER (WHERE direction='C'), 0)
      INTO debit_total, credit_total
      FROM wallet_schema.ledger_entries
      WHERE transaction_id = NEW.transaction_id;

      IF debit_total != credit_total THEN
          RAISE EXCEPTION
              'Double-entry violation: txn=% debit=% credit=%',
              NEW.transaction_id, debit_total, credit_total
              USING ERRCODE = 'check_violation';
      END IF;

      RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  CREATE CONSTRAINT TRIGGER ledger_balance_check
  AFTER INSERT ON wallet_schema.ledger_entries
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION wallet_schema.enforce_double_entry();

32-wallet-rules.sql:
  CREATE RULE no_update_ledger AS
      ON UPDATE TO wallet_schema.ledger_entries DO INSTEAD NOTHING;
  CREATE RULE no_delete_ledger AS
      ON DELETE FROM wallet_schema.ledger_entries DO INSTEAD NOTHING;
  CREATE RULE no_update_transactions AS
      ON UPDATE TO wallet_schema.transactions DO INSTEAD NOTHING;
  CREATE RULE no_delete_transactions AS
      ON DELETE FROM wallet_schema.transactions DO INSTEAD NOTHING;

33-wallet-outbox.sql:
  CREATE TABLE wallet_schema.outbox (
      id              BIGSERIAL PRIMARY KEY,
      aggregate       TEXT NOT NULL,
      event_type      TEXT NOT NULL,
      payload         JSONB NOT NULL,
      idempotency_key TEXT NOT NULL UNIQUE,
      trace_id        TEXT,
      span_id         TEXT,
      published_at    TIMESTAMPTZ,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX outbox_unpublished_idx
      ON wallet_schema.outbox(created_at) WHERE published_at IS NULL;

34-wallet-alerts.sql:
  CREATE TABLE wallet_schema.ledger_alerts (
      id            BIGSERIAL PRIMARY KEY,
      severity      TEXT NOT NULL,                 -- 'INFO','WARN','CRITICAL'
      message       TEXT NOT NULL,
      detected_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
      acknowledged  BOOLEAN NOT NULL DEFAULT FALSE
  );

40-commission-schema.sql:
  -- Phase 2 will add accruals, rules, settlements tables.
  -- For now, schema exists, owner is commission_user. No tables.

50-treasury-schema.sql:
  -- Phase 2 will add float_positions, bank_movements tables.
  -- For now, schema exists, owner is treasury_user. No tables.

60-grants.sql:
  - Each module role gets only USAGE on its own schema and SELECT/INSERT on its tables.
  - wallet_user gets SELECT, INSERT on wallet_schema.* (UPDATE/DELETE blocked by RULES even if attempted).
  - commission_user and treasury_user follow the same pattern in their schemas.

99-set-passwords.sh: same pattern as postgres-ecom; reads WALLET_DB_PASSWORD, COMMISSION_DB_PASSWORD, TREASURY_DB_PASSWORD from env and ALTER USER on each.

Add /deploy/postgres-ledger/postgresql.conf with parameters from INFRASTRUCTURE.md § 16.3 (shared_buffers=1GB, effective_cache_size=3GB, max_connections=50, fsync=on, synchronous_commit=on, log_statement='mod' for audit, log_min_duration_statement=100, log_connections=on, log_disconnections=on).

After containers are running, verify with:

  -- 1. Append-only enforcement test (must fail or no-op):
  -- (open psql as wallet_user)
  INSERT INTO wallet_schema.accounts (type) VALUES ('test_asset');
  INSERT INTO wallet_schema.transactions (type, idempotency_key) VALUES ('test', 'idem-1');
  INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor) VALUES (1,1,'D',100);
  INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor) VALUES (1,1,'C',100);
  -- Both inserts should succeed at COMMIT.

  -- 2. Imbalance test (must fail at commit):
  BEGIN;
  INSERT INTO wallet_schema.transactions (type, idempotency_key) VALUES ('test2', 'idem-2');
  INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor) VALUES (2,1,'D',100);
  INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor) VALUES (2,1,'C',50);
  COMMIT;
  -- Expected: ERROR: Double-entry violation

  -- 3. Append-only enforcement (UPDATE must be a no-op):
  UPDATE wallet_schema.ledger_entries SET amount_minor = 999 WHERE id = 1;
  -- Expected: 0 rows updated (RULE rewrites it).

DO NOT seed any production accounts here. Production chart-of-accounts seeding is Phase 2 work and goes through migrations.

DO NOT use float types anywhere. amount_minor is BIGINT.
```

**Verification / Done Criteria:**
- [ ] All eleven init files exist exactly as specified.
- [ ] `\dn` shows wallet_schema, commission_schema, treasury_schema.
- [ ] `\dt wallet_schema.*` shows accounts, transactions, ledger_entries, outbox, ledger_alerts.
- [ ] D=C imbalance test produces `ERROR: check_violation` at COMMIT.
- [ ] UPDATE on ledger_entries reports 0 rows affected (silently rewritten by RULE).
- [ ] DELETE on transactions reports 0 rows affected.
- [ ] postgres-ledger is on mopro-fin-net only (verified by `docker network inspect mopro-fin-net`).
- [ ] core-svc and jobs-svc cannot reach postgres-ledger:5432 (verified by `docker exec core-svc nc -zv postgres-ledger 5432` returning network-unreachable).

---

## Prompt 0.4 — Implement EventBus over Redis Streams + Outbox Publisher

**Phase & Goal:** Phase 0. Build the shared `internal/eventbus` package with a Publisher / Subscriber interface and a Redis Streams implementation, plus the `internal/outbox` publisher worker that drains outbox tables into the bus. Both are used by Phase 2+ business code.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: ARCHITECTURE.md § 8, LEDGER_GUIDE.md § 5 and § 6, CLAUDE.md § 3 and § 4.4.

Implement the EventBus and Outbox publisher as shared packages used by core-svc, fin-svc, and jobs-svc.

PATHS TO CREATE:

/internal/eventbus/topics.go
/internal/eventbus/event.go
/internal/eventbus/publisher.go
/internal/eventbus/subscriber.go
/internal/eventbus/redis_bus.go
/internal/eventbus/dlq.go
/internal/eventbus/eventbus_test.go

/internal/outbox/row.go
/internal/outbox/store.go
/internal/outbox/publisher.go
/internal/outbox/publisher_test.go

REQUIREMENTS:

1. /internal/eventbus/topics.go
   Define topic constants. Naming convention <domain>.<entity>.<action>.v<n>.

   const (
       TopicOrderCompletedV1            = "ecom.order.completed.v1"
       TopicPaymentCapturedV1           = "ecom.payment.captured.v1"
       TopicCommissionAccruedV1         = "fin.commission.accrued.v1"
       TopicCommissionRefundRequestedV1 = "fin.commission.refund_requested.v1"
       TopicCommissionRefundPostedV1    = "fin.commission.refund_posted.v1"
       TopicWithdrawRequestedV1         = "fin.withdraw.requested.v1"
       TopicWithdrawCompletedV1         = "fin.withdraw.completed.v1"
       TopicNotificationRequestedV1     = "jobs.notification.requested.v1"
   )

2. /internal/eventbus/event.go
   type Event struct {
       Topic          string    `json:"topic"`
       EventID        string    `json:"event_id"`        // UUID v4
       OccurredAt     time.Time `json:"occurred_at"`     // RFC3339Nano
       IdempotencyKey string    `json:"idempotency_key"`
       TraceID        string    `json:"trace_id"`
       SpanID         string    `json:"span_id"`
       Payload        json.RawMessage `json:"payload"`
   }
   func NewEvent(topic, idemKey string, payload any) (Event, error)
   // NewEvent fills EventID with uuid.New(), OccurredAt with time.Now().UTC().

3. /internal/eventbus/publisher.go
   type Publisher interface {
       Publish(ctx context.Context, ev Event) error
   }

4. /internal/eventbus/subscriber.go
   type Handler func(ctx context.Context, ev Event) error

   type Subscriber interface {
       // Subscribe registers a Handler for a topic under a consumer group.
       // Group ensures multiple instances share work; pendingTimeout reclaims hung messages.
       Subscribe(topic, group, consumer string, h Handler) error
       Run(ctx context.Context) error
       Stop(ctx context.Context) error
   }

5. /internal/eventbus/redis_bus.go
   - RedisBus struct holds *redis.Client and config (maxLen for trim, blockTimeout, pendingTimeout, dlqTopic).
   - NewRedisBus(cfg Config) *RedisBus.
   - Publish: enforces ev.TraceID != "" (return ErrTraceRequired); calls XAdd with MAXLEN ~ 10000 (approx) and Values map: event_id, idempotency_key, trace_id, span_id, payload, occurred_at, topic.
   - Subscribe: stores handler registrations. Run loops over registered subscriptions, calling XREADGROUP per group with COUNT=10, BLOCK=2s. Acks via XACK on success. On handler error, increments retry counter using XCLAIM; after 5 retries, calls dlq.Push(ev) and XACKs to clear pending.
   - All XREADGROUP/XADD calls accept ctx and respect cancellation.
   - Use go-redis/v9.

6. /internal/eventbus/dlq.go
   type DLQ interface {
       Push(ctx context.Context, ev Event, err error) error
   }
   type RedisDLQ struct { client *redis.Client; stream string }
   // Pushes to a separate stream (e.g., "<topic>.dlq") with the original event + error message and a "first_failed_at"/"last_failed_at"/"failure_count" trio.
   // The mopro CLI later reads from this stream for replay tooling.

7. /internal/outbox/row.go
   type Row struct {
       ID             int64
       Aggregate      string
       EventType      string
       Payload        json.RawMessage
       IdempotencyKey string
       TraceID        string
       SpanID         string
       CreatedAt      time.Time
   }

8. /internal/outbox/store.go
   type Store interface {
       Insert(ctx context.Context, tx pgx.Tx, r Row) error
       FetchUnpublished(ctx context.Context, limit int) ([]Row, error)
       MarkPublished(ctx context.Context, id int64) error
   }
   // Two implementations: one for postgres-ecom (uses order_schema.outbox or similar per-module), and one for postgres-ledger (wallet_schema.outbox). Choose by which DB pool you pass in.

9. /internal/outbox/publisher.go
   type Publisher struct {
       store Store
       bus   eventbus.Publisher
       interval time.Duration
       batch    int
   }
   // Run loops every Publisher.interval (default 250ms): FetchUnpublished(batch=100), for each row build eventbus.Event, call bus.Publish, on success MarkPublished. Errors are logged but do not crash; the next tick retries.
   // Crucially: idempotency_key on bus.Publish is the row's idempotency_key, NOT a fresh one — so re-publish is safe.

10. /internal/eventbus/eventbus_test.go and /internal/outbox/publisher_test.go
   - Use miniredis or testcontainers for Redis.
   - Property test: publish 10000 events; consumer must see exactly each idempotency_key at least once.
   - DLQ test: handler that always errors → after 5 retries, event lands on <topic>.dlq.
   - Outbox publisher test: insert 100 rows; after one Run iteration, they are all published and marked.

DO NOT add HTTP. EventBus is a library, not a server.
DO NOT use channels for cross-process delivery; Redis Streams only.
DO NOT bypass the bus when publishing financial events — the LEDGER_GUIDE.md outbox rule still applies.

When done, run `go test ./internal/eventbus/... ./internal/outbox/...` and report.
```

**Verification / Done Criteria:**
- [ ] `go build ./internal/eventbus/... ./internal/outbox/...` succeeds.
- [ ] `go test ./internal/eventbus/... ./internal/outbox/...` passes.
- [ ] Property test publishes ≥ 10,000 events without loss.
- [ ] DLQ test routes a permanently-failing event after 5 retries.
- [ ] `golangci-lint run ./internal/eventbus/... ./internal/outbox/...` is clean.
- [ ] No file in `/internal/eventbus/` or `/internal/outbox/` imports any module package (`/internal/wallet`, etc.).
- [ ] `RedisBus.Publish` rejects events without TraceID (`ErrTraceRequired`).

---

## Prompt 0.5 — Bootstrap Docker Compose Stack

**Phase & Goal:** Phase 0. Wire all containers (Caddy, two Postgres, two PgBouncer, Redis, Meilisearch, three Go binaries, Grafana Agent) into a single `docker compose up` that runs locally and on the production VDS.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: ARCHITECTURE.md, INFRASTRUCTURE.md (especially § 5 hardening and § 2 RAM table), CLAUDE.md § 7.

Produce /deploy/docker-compose.yml that boots the full stack with all hardening flags, mem_limits, and network isolation per PRD v3.2.

REQUIREMENTS:

1. Two networks:
     mopro-net      bridge, subnet 172.30.0.0/24
     mopro-fin-net  bridge, subnet 172.31.0.0/24

2. YAML anchor x-go-defaults with the entire hardening block from INFRASTRUCTURE.md § 5 (mem_limit 384m, mem_reservation 192m, cpus 0.5, pids_limit 256, security_opt no-new-privileges:true, cap_drop ALL, read_only true, tmpfs /tmp 64M, ulimits, json-file logging max 20m × 5).

3. Services:

   caddy:
     image caddy:2-alpine
     ports 80, 443
     mem_limit 256m, cpus 0.5
     security_opt no-new-privileges:true
     volumes:
       ./caddy/Caddyfile -> /etc/caddy/Caddyfile (ro)
       caddy_data, caddy_config (named volumes)
     networks: [mopro-net]

   postgres-ecom:
     image postgres:16-alpine
     mem_limit 5g, mem_reservation 3g, cpus 2.0, shm_size 256m
     read_only false
     security_opt no-new-privileges:true
     cap_drop ALL
     cap_add CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID
     environment: POSTGRES_DB=mopro_ecom, POSTGRES_USER=ecom_admin, POSTGRES_PASSWORD=${ECOM_DB_PASSWORD}
     volumes:
       ./data/postgres-ecom -> /var/lib/postgresql/data
       ./postgres-ecom/init -> /docker-entrypoint-initdb.d (ro)
       ./postgres-ecom/postgresql.conf -> /etc/postgresql/postgresql.conf (ro)
     command: ["postgres","-c","config_file=/etc/postgresql/postgresql.conf"]
     healthcheck: pg_isready
     networks: [mopro-net]

   postgres-ledger:
     image postgres:16-alpine
     mem_limit 3g, mem_reservation 2g, cpus 1.5, shm_size 128m
     read_only false
     security flags same as postgres-ecom
     environment: POSTGRES_DB=mopro_ledger, POSTGRES_USER=ledger_admin, POSTGRES_PASSWORD=${LEDGER_DB_PASSWORD}
     volumes:
       ./data/postgres-ledger -> /var/lib/postgresql/data
       ./postgres-ledger/init -> /docker-entrypoint-initdb.d (ro)
       ./postgres-ledger/postgresql.conf -> /etc/postgresql/postgresql.conf (ro)
     networks: [mopro-fin-net]    # ONLY this network — critical isolation

   pgbouncer-ecom:
     image edoburu/pgbouncer:latest
     mem_limit 100m, cpus 0.2
     security_opt no-new-privileges:true
     environment:
       DATABASE_URL=postgres://ecom_admin:${ECOM_DB_PASSWORD}@postgres-ecom:5432/mopro_ecom
       POOL_MODE=transaction
       MAX_CLIENT_CONN=500
       DEFAULT_POOL_SIZE=30
     networks: [mopro-net]
     depends_on: [postgres-ecom]

   pgbouncer-ledger:
     image edoburu/pgbouncer:latest
     mem_limit 100m, cpus 0.2
     environment:
       DATABASE_URL=postgres://ledger_admin:${LEDGER_DB_PASSWORD}@postgres-ledger:5432/mopro_ledger
       POOL_MODE=transaction
       MAX_CLIENT_CONN=200
       DEFAULT_POOL_SIZE=20
     networks: [mopro-fin-net]
     depends_on: [postgres-ledger]

   redis:
     image redis:7-alpine
     mem_limit 1.2g, cpus 1.0
     security_opt no-new-privileges:true
     command: ["redis-server","/usr/local/etc/redis/redis.conf"]
     volumes:
       ./redis/redis.conf -> /usr/local/etc/redis/redis.conf (ro)
       ./data/redis -> /data
     networks: [mopro-net]

   meilisearch:
     image getmeili/meilisearch:v1.6
     mem_limit 1.5g, cpus 1.0
     security_opt no-new-privileges:true
     environment:
       MEILI_ENV=production
       MEILI_MASTER_KEY=${MEILI_MASTER_KEY}
       MEILI_NO_ANALYTICS=true
     volumes:
       ./data/meilisearch -> /meili_data
     networks: [mopro-net]

   core-svc:
     <<: *go-defaults
     image: ghcr.io/mopro/core-svc:${CORE_TAG:-dev}
     environment: SVC_NAME=core-svc, ENV=production, DB_HOST=pgbouncer-ecom, DB_PORT=5432, DB_NAME=mopro_ecom, REDIS_URL=redis://redis:6379/0, JWT_SIGNING_KEY=${JWT_SIGNING_KEY}, PII_KEK_BASE64=${PII_KEK_BASE64}
     # Inherits networks: [mopro-net] from go-defaults

   fin-svc:
     <<: *go-defaults
     image: ghcr.io/mopro/fin-svc:${FIN_TAG:-dev}
     environment: SVC_NAME=fin-svc, ENV=production, DB_HOST=pgbouncer-ledger, DB_PORT=5432, DB_NAME=mopro_ledger, DB_USER=wallet_user, DB_PASSWORD=${WALLET_DB_PASSWORD}, REDIS_URL=redis://redis:6379/0, PII_KEK_BASE64=${PII_KEK_BASE64}
     networks: [mopro-net, mopro-fin-net]   # two networks: redis on ecom side, ledger on fin side

   jobs-svc:
     <<: *go-defaults
     image: ghcr.io/mopro/jobs-svc:${JOBS_TAG:-dev}
     environment: SVC_NAME=jobs-svc, ENV=production, DB_HOST=pgbouncer-ecom, DB_PORT=5432, DB_NAME=mopro_ecom, REDIS_URL=redis://redis:6379/0, FCM_SERVER_KEY=${FCM_SERVER_KEY}

   grafana-agent:
     image: grafana/agent:latest
     mem_limit 300m, cpus 0.3
     security_opt no-new-privileges:true
     volumes:
       ./grafana-agent/agent.yaml -> /etc/agent.yaml (ro)
       /var/run/docker.sock -> /var/run/docker.sock (ro)
       /var/log -> /var/log (ro)
     command: ["-config.file=/etc/agent.yaml"]
     networks: [mopro-net]

4. Volumes (named): caddy_data, caddy_config.

5. Compose-level YAML anchor for healthcheck retries and start_period for Postgres (start_period 30s, retries 5).

6. Ensure restart: unless-stopped on all services.

7. Add a separate /deploy/docker-compose.dev.yml override that:
     - Removes read_only and security_opt for easier local dev.
     - Adds bind mounts for live source code (only in dev override, never in prod).
     - Maps Postgres ports 5432 and 5433 to host (only in dev).

VERIFY:
  docker compose --env-file .env.local up -d
  docker compose --env-file .env.local ps     # all healthy
  docker network inspect mopro-fin-net        # only fin-svc, pgbouncer-ledger, postgres-ledger
  docker network inspect mopro-net            # rest
  docker exec core-svc nc -zv postgres-ledger 5432    # MUST FAIL (network-unreachable)
  docker exec fin-svc nc -zv postgres-ledger 5432     # MUST SUCCEED
  docker exec fin-svc nc -zv redis 6379               # MUST SUCCEED

DO NOT mount /var/run/docker.sock into any application container (only grafana-agent, read-only).
DO NOT publish Postgres or Redis ports on the host in production. Only in dev override.
DO NOT use the same password for ECOM_DB_PASSWORD and LEDGER_DB_PASSWORD.
```

**Verification / Done Criteria:**
- [ ] `docker compose --env-file .env.local up -d` brings every service to healthy.
- [ ] `docker network inspect mopro-fin-net` lists only fin-svc, pgbouncer-ledger, postgres-ledger.
- [ ] core-svc cannot reach postgres-ledger (TCP refused / unreachable).
- [ ] fin-svc reaches both Redis and postgres-ledger.
- [ ] No application container (other than grafana-agent) has docker.sock mounted.
- [ ] No service runs as root (`docker exec <svc> id` shows nonroot UID 65532).
- [ ] All x-go-defaults flags applied to core-svc, fin-svc, jobs-svc.

---

## Prompt 0.6 — Configure Caddy Reverse Proxy with TLS and Base Routes

**Phase & Goal:** Phase 0. Stand up Caddy with automatic Let's Encrypt, JSON access logs, baseline rate-limit, and `/healthz` route. Module-specific routes are added in Phase 1.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: ARCHITECTURE.md § 1, PROMPTS.md Prompt 0.5.

Create /deploy/caddy/Caddyfile and ensure it auto-reloads cleanly.

REQUIREMENTS:

Global block:
  {
      email ${CADDY_EMAIL}
      admin off
      servers {
          protocols h1 h2 h3
      }
      log default {
          output stderr
          format json
          level INFO
      }
  }

api.moproshop.com host block:
  encode zstd gzip

  # Default per-IP rate limit
  rate_limit {
      zone per_ip {
          key {remote_host}
          events 600
          window 1m
      }
  }

  # Health and metrics for upstream probes (reachable from internal only via header check)
  @internal {
      header X-Internal-Probe "true"
      path /healthz /metrics
  }
  handle @internal {
      reverse_proxy core-svc:9090
  }

  # Public health check (no auth, very small payload)
  handle /healthz {
      respond "ok" 200
  }

  # Phase 1+ adds /v1/* matchers. Until then, default 404:
  handle {
      respond 404
  }

  log {
      output file /var/log/caddy/api.log {
          roll_size 100mb
          roll_keep 7
      }
      format json
  }

seller.moproshop.com host block:
  # Will route to seller-panel-web in a future phase. For now respond 503 maintenance.
  handle { respond 503 }

img.moproshop.com host block:
  reverse_proxy https://f000.backblazeb2.com/file/mopro-media {
      header_up Host {upstream_hostport}
  }
  header Cache-Control "public, max-age=2592000"

For local dev (the dev override): the host can be `localhost` and TLS internal/self-signed. Do not use real ACME against a domain you do not own.

Add a /deploy/caddy/README.md with:
  - How to reload: docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
  - How to validate: docker run --rm -v $(pwd)/Caddyfile:/etc/caddy/Caddyfile caddy:2 caddy validate --config /etc/caddy/Caddyfile

VERIFY:
  curl -sf http://localhost/healthz   # → ok
  curl -sf http://localhost/v1/test    # → 404 (no matcher yet)
  docker compose logs caddy | head -50

DO NOT expose Caddy admin API.
DO NOT add routes for modules that are not implemented yet.
DO NOT add basic_auth on the public API (auth is the identity module's job in Phase 1).
```

**Verification / Done Criteria:**
- [ ] `caddy validate` returns success.
- [ ] `/healthz` returns 200 with body "ok".
- [ ] `/v1/anything` returns 404.
- [ ] Access logs are JSON in /var/log/caddy/api.log.
- [ ] No host header other than the configured ones gets a successful response.
- [ ] Caddy reload does not drop active connections (test with a long-running curl during reload).

---

# PHASE 1 — E-Commerce Core

The goal of Phase 1 is to bring the catalog, cart, order, payment, seller, and search modules online inside core-svc, and to expose them via Caddy.

## Prompt 1.1 — Create catalog Module in core-svc

**Phase & Goal:** Phase 1. Build the catalog module with its public interface, repository, domain types, schema migration, and tests. The pattern set here is the template for cart, order, seller, and search modules.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: CLAUDE.md § 2.3 and § 3.1, DATA_DICTIONARY.md (especially § 2.1 and § 3 cross-schema ban), DEVELOPMENT.md § 9 (depguard).

Create the catalog module inside core-svc.

PATHS:

/internal/catalog/api.go
/internal/catalog/service.go
/internal/catalog/repository.go
/internal/catalog/domain.go
/internal/catalog/errors.go
/internal/catalog/api_test.go
/internal/catalog/service_test.go
/internal/catalog/repository_integration_test.go
/migrations/ecom/0010_create_catalog_schema.sql
/migrations/ecom/0011_create_catalog_products.sql
/migrations/ecom/0012_create_catalog_variants.sql
/migrations/ecom/0013_create_catalog_categories.sql
/migrations/ecom/0014_create_catalog_indexes.sql

REQUIREMENTS:

1. domain.go:

   type Category struct { ID int64; ParentID *int64; Name string; AttributesSchema json.RawMessage; CreatedAt time.Time }
   type Product struct { ID int64; SellerID int64; Title string; Description string; Brand string; CategoryID int64; Status string; CreatedAt time.Time; UpdatedAt time.Time }
   type Variant struct { ID int64; ProductID int64; SKU string; Color string; Size string; PriceMinor int64; Stock int32; ImageKeys []string }

   Status enum: 'draft','active','archived'.
   PriceMinor is BIGINT minor units (kuruş). Do not use float.

2. errors.go (sentinel errors):

   var (
       ErrProductNotFound  = errors.New("catalog: product not found")
       ErrVariantNotFound  = errors.New("catalog: variant not found")
       ErrCategoryNotFound = errors.New("catalog: category not found")
       ErrInvalidStatus    = errors.New("catalog: invalid status")
       ErrSKUConflict      = errors.New("catalog: sku already exists for product")
   )

3. api.go (the ONLY file other modules import):

   package catalog
   import "context"

   type Service interface {
       CreateProduct(ctx context.Context, in CreateProductInput) (Product, error)
       GetProduct(ctx context.Context, id int64) (Product, error)
       ListProducts(ctx context.Context, q ListQuery) ([]Product, string, error)   // returns slice + next cursor
       AddVariant(ctx context.Context, productID int64, in CreateVariantInput) (Variant, error)
       GetVariant(ctx context.Context, id int64) (Variant, error)
       AdjustStock(ctx context.Context, variantID int64, delta int32, reason string, idemKey string) error
   }

   type Repository interface {
       InsertProduct(ctx context.Context, p Product) (int64, error)
       FindProductByID(ctx context.Context, id int64) (Product, error)
       FindProductsByCursor(ctx context.Context, q ListQuery) ([]Product, string, error)
       InsertVariant(ctx context.Context, v Variant) (int64, error)
       FindVariantByID(ctx context.Context, id int64) (Variant, error)
       AdjustVariantStock(ctx context.Context, variantID int64, delta int32, idemKey string) error
   }

   The Repository interface must NEVER expose raw *sql.Rows or pgx-specific types.

4. service.go:
   - Implements Service.
   - AdjustStock uses an idempotency_key UNIQUE table (catalog_schema.stock_adjustments(idempotency_key UNIQUE)) to deduplicate retries.
   - All methods accept context.Context and propagate it.
   - Validation happens in service, not repository.

5. repository.go:
   - Uses pgx.Pool injected via constructor.
   - All queries scoped to catalog_schema. NEVER read another module's schema.
   - Cursor encoding: base64({"id": <int>, "created_at": "<rfc3339>"}).

6. Migrations:

   0010_create_catalog_schema.sql — already created in Prompt 0.2 init script; this file is no-op or a sanity assertion.

   0011_create_catalog_products.sql:
     CREATE TABLE catalog_schema.products (
       id BIGSERIAL PRIMARY KEY,
       seller_id BIGINT NOT NULL,
       title TEXT NOT NULL,
       description TEXT NOT NULL DEFAULT '',
       brand TEXT NOT NULL DEFAULT '',
       category_id BIGINT NOT NULL,
       status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','archived')),
       created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
       updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
     );

   0012_create_catalog_variants.sql:
     CREATE TABLE catalog_schema.variants (
       id BIGSERIAL PRIMARY KEY,
       product_id BIGINT NOT NULL REFERENCES catalog_schema.products(id),
       sku TEXT NOT NULL,
       color TEXT NOT NULL DEFAULT '',
       size TEXT NOT NULL DEFAULT '',
       price_minor BIGINT NOT NULL CHECK (price_minor >= 0),
       stock INTEGER NOT NULL DEFAULT 0,
       image_keys TEXT[] NOT NULL DEFAULT '{}'::text[],
       created_at TIMESTAMPTZ NOT NULL DEFAULT now()
     );
     CREATE UNIQUE INDEX variants_product_sku_uq ON catalog_schema.variants(product_id, sku);

   0013_create_catalog_categories.sql:
     CREATE TABLE catalog_schema.categories (
       id BIGSERIAL PRIMARY KEY,
       parent_id BIGINT REFERENCES catalog_schema.categories(id),
       name TEXT NOT NULL,
       attributes_schema JSONB NOT NULL DEFAULT '{}'::jsonb,
       created_at TIMESTAMPTZ NOT NULL DEFAULT now()
     );

     CREATE TABLE catalog_schema.stock_adjustments (
       id BIGSERIAL PRIMARY KEY,
       variant_id BIGINT NOT NULL REFERENCES catalog_schema.variants(id),
       delta INTEGER NOT NULL,
       reason TEXT NOT NULL,
       idempotency_key TEXT NOT NULL UNIQUE,
       created_at TIMESTAMPTZ NOT NULL DEFAULT now()
     );

   0014_create_catalog_indexes.sql:
     CREATE INDEX CONCURRENTLY products_status_idx ON catalog_schema.products(status);
     CREATE INDEX CONCURRENTLY products_category_idx ON catalog_schema.products(category_id);
     CREATE INDEX CONCURRENTLY products_seller_idx ON catalog_schema.products(seller_id);
     CREATE INDEX CONCURRENTLY products_created_at_idx ON catalog_schema.products(created_at DESC);

   NEVER use FK to other schemas. seller_id is a BIGINT but does NOT carry a REFERENCES clause to seller_schema.sellers.

7. Tests:
   - api_test.go uses a fake Repository. Asserts service contracts.
   - service_test.go: validation cases (empty title, negative price, invalid status, idempotency replay).
   - repository_integration_test.go uses testcontainers to spin a real Postgres and applies migrations 0010–0014. Build tag: integration.

8. Wire up in /cmd/core-svc/main.go:
   - Build a pgx pool to pgbouncer-ecom:5432.
   - Construct catalog.Repository (concrete) → catalog.Service (concrete).
   - Register HTTP handlers under /v1/catalog/* (define in /internal/catalog/http_handler.go).

9. Forbidden:
   - import "github.com/mopro/platform/internal/wallet" → fails depguard.
   - SQL like SELECT ... FROM order_schema.orders inside catalog → fails check-module-boundaries.sh.
   - float64 for any price/amount field.
   - DROP, ALTER COLUMN TYPE, RENAME in any migration.

When done, run:
  go test ./internal/catalog/...
  go test -tags=integration ./internal/catalog/...
  golangci-lint run ./internal/catalog/...
  ./scripts/check-module-boundaries.sh
```

**Verification / Done Criteria:**
- [ ] All eleven listed paths exist.
- [ ] `go test ./internal/catalog/...` passes.
- [ ] `go test -tags=integration ./internal/catalog/...` passes.
- [ ] `golangci-lint run ./internal/catalog/...` is clean.
- [ ] `./scripts/check-module-boundaries.sh` is clean.
- [ ] `migrate-tool ecom up` runs all four catalog migrations without error.
- [ ] `\dt catalog_schema.*` shows products, variants, categories, stock_adjustments.
- [ ] AdjustStock with the same idempotency_key applied twice changes stock only once (test case present).
- [ ] No FK declared from catalog tables to any other schema.

---

## Prompt 1.2 — Create cart Module + Redis-Backed Sessions

**Phase & Goal:** Phase 1. Cart module persists per-user cart state in Redis with a Postgres fallback for durability. The pattern includes idempotency on add/remove and atomic stock reservation via a Lua script.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: CLAUDE.md, DATA_DICTIONARY.md, ARCHITECTURE.md § 4.1.

Create the cart module inside core-svc.

PATHS:

/internal/cart/api.go
/internal/cart/service.go
/internal/cart/repository.go
/internal/cart/redis_store.go
/internal/cart/lua/reserve_stock.lua
/internal/cart/domain.go
/internal/cart/errors.go
/internal/cart/http_handler.go
/internal/cart/{api,service,redis_store}_test.go
/migrations/ecom/0020_create_cart_schema.sql
/migrations/ecom/0021_create_cart_durable.sql

REQUIREMENTS:

1. domain.go:
   type Cart struct { ID string; UserID int64; Items []CartItem; UpdatedAt time.Time }
   type CartItem struct { VariantID int64; Qty int32; UnitPriceMinor int64; SellerID int64 }

2. api.go (Service interface):
   AddItem(ctx, userID, variantID, qty, idemKey) (Cart, error)
   RemoveItem(ctx, userID, variantID, idemKey) (Cart, error)
   Get(ctx, userID) (Cart, error)
   ReserveForCheckout(ctx, userID, idemKey) (reservationID string, err error)  // calls catalog.AdjustStock via service injection
   ReleaseReservation(ctx, reservationID) error

3. redis_store.go:
   - Hash key: cart:{user_id}
   - JSON-encoded Cart per user.
   - TTL: 14 days; refreshed on every write.
   - Idempotency cache key: cart_idem:{user_id}:{idem_key} → "<sha256 of result body>", TTL 24h.

4. lua/reserve_stock.lua:
   - Atomic decrement of `stock:{variant_id}` Redis counter; reverts on failure.
   - Returns 1 on success, 0 on insufficient stock.
   - Loaded once at startup via SCRIPT LOAD; called via EVALSHA for performance.

5. repository.go (Postgres fallback for durability and analytics):
   - cart_schema.cart_snapshots(user_id BIGINT, payload JSONB, updated_at TIMESTAMPTZ).
   - Snapshot every cart write asynchronously (fire-and-forget; not blocking the response).

6. service.go:
   - Coordinates Redis (live cart) + Postgres (durable snapshot) + catalog.Service (price/stock lookup).
   - ReserveForCheckout calls into catalog.Service via the Service interface (NOT into catalog.Repository).
   - Holds a reservation lock in Redis: lock:reservation:{user_id} via SETNX with 5-minute TTL.

7. http_handler.go:
   - POST /v1/cart/items, DELETE /v1/cart/items/{variant_id}, GET /v1/cart, POST /v1/cart/checkout/reserve.
   - All POST/DELETE require Idempotency-Key header (return 400 if missing).

8. Migrations:
   0020 — schema (no-op; already created in Prompt 0.2).
   0021_create_cart_durable.sql:
     CREATE TABLE cart_schema.cart_snapshots (
       user_id BIGINT PRIMARY KEY,
       payload JSONB NOT NULL,
       updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
     );

9. Tests:
   - service_test.go: ConcurrentAdd → final qty correct.
   - redis_store_test.go: Idempotency replay returns identical cart.
   - reserve_stock test: 100 goroutines reserving 1 each from a stock of 50 → exactly 50 succeed.

10. Wire to /cmd/core-svc/main.go.

DO NOT cross-import internal/catalog/repository.
DO NOT use pessimistic Postgres locks for cart; Redis is the source of truth.
DO NOT log full cart payloads (PII risk).
```

**Verification / Done Criteria:**
- [ ] go test passes including the high-concurrency reservation test.
- [ ] Idempotency-Key header missing → 400.
- [ ] Adding the same item twice with same Idempotency-Key returns identical cart.
- [ ] catalog imports remain through the public Service interface only.

---

## Prompt 1.3 — Create order Module with Saga Orchestration

**Phase & Goal:** Phase 1. The order module orchestrates checkout: validate cart → reserve stock → create payment → write order + outbox row → return order_id. This is the producer side of the order.completed saga.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: CLAUDE.md § 4 (financial invariants apply because outbox writes here too), ARCHITECTURE.md § 5, PROMPTS.md Prompt 1.1 and 1.2.

Create the order module inside core-svc.

PATHS:

/internal/order/api.go
/internal/order/service.go
/internal/order/repository.go
/internal/order/saga.go
/internal/order/domain.go
/internal/order/errors.go
/internal/order/http_handler.go
/internal/order/{api,service,saga}_test.go
/migrations/ecom/0030_create_order_schema.sql
/migrations/ecom/0031_create_order_tables.sql
/migrations/ecom/0032_create_order_outbox.sql

REQUIREMENTS:

1. domain.go:
   type Order struct {
       ID int64; UserID int64; Status string; TotalMinor int64; Currency string;
       Items []OrderItem; CreatedAt, UpdatedAt time.Time;
   }
   type OrderItem struct {
       ID int64; OrderID int64; VariantID int64; SellerID int64;
       Qty int32; UnitPriceMinor int64; CommissionRuleID *int64;
   }

   Status enum: 'pending_payment','paid','shipped','delivered','cancelled','refunded'.
   Currency: always 'TRY'.

2. api.go (Service):
   Checkout(ctx, in CheckoutInput) (Order, paymentURL string, err error)
   GetByID(ctx, id int64, userID int64) (Order, error)
   ListByUser(ctx, userID int64, cursor string) ([]Order, string, error)
   Cancel(ctx, id int64, userID int64, idemKey string) error

3. saga.go orchestrates checkout:

   func (s *service) Checkout(ctx context.Context, in CheckoutInput) (Order, string, error) {
       if in.IdempotencyKey == "" { return Order{}, "", ErrIdempotencyKeyRequired }
       // 1. Cart freeze + reservation
       reservationID, err := s.cart.ReserveForCheckout(ctx, in.UserID, in.IdempotencyKey)
       if err != nil { return Order{}, "", err }
       defer func() {
           if err != nil { _ = s.cart.ReleaseReservation(ctx, reservationID) }
       }()

       // 2. Compute totals (NOT in DB tx; pure calculation)
       cart, _ := s.cart.Get(ctx, in.UserID)
       total := computeTotal(cart)

       // 3. Open Postgres tx (SERIALIZABLE)
       var orderID int64; var paymentURL string
       err = s.repo.WithTx(ctx, sql.LevelSerializable, func(tx pgx.Tx) error {
           // 3a. Insert order + items
           orderID, err = s.repo.InsertOrder(ctx, tx, Order{...})
           if err != nil { return err }

           // 3b. Initiate payment via payment.Service (in-memory call inside core-svc)
           paymentURL, err = s.payment.CreateAttempt(ctx, tx, orderID, total, in.IdempotencyKey)
           if err != nil { return err }

           // 3c. Write outbox row in SAME tx
           return s.outbox.Insert(ctx, tx, outbox.Row{
               Aggregate:      "order",
               EventType:      eventbus.TopicOrderCompletedV1,   // emitted only on payment.captured later
               Payload:        marshalCheckoutPayload(orderID, in),
               IdempotencyKey: in.IdempotencyKey,
               TraceID:        traceIDFromCtx(ctx),
           })
       })
       if err != nil { return Order{}, "", err }
       order, _ := s.repo.GetByID(ctx, orderID)
       return order, paymentURL, nil
   }

   NOTE: The actual order.completed event is published only after payment.captured (Phase 3 wires this). Phase 1 just persists the outbox row in 'pending_payment' state and the publisher worker holds it; the saga prompt in Phase 3 makes the publisher conditional on payment status.

4. repository.go: pgx, scoped strictly to order_schema.

5. Migrations:

   0031_create_order_tables.sql:
     CREATE TABLE order_schema.orders (
       id BIGSERIAL PRIMARY KEY,
       user_id BIGINT NOT NULL,
       status TEXT NOT NULL CHECK (status IN ('pending_payment','paid','shipped','delivered','cancelled','refunded')),
       total_minor BIGINT NOT NULL CHECK (total_minor >= 0),
       currency TEXT NOT NULL DEFAULT 'TRY',
       idempotency_key TEXT NOT NULL UNIQUE,
       created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
       updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
     );

     CREATE TABLE order_schema.order_items (
       id BIGSERIAL PRIMARY KEY,
       order_id BIGINT NOT NULL REFERENCES order_schema.orders(id),
       variant_id BIGINT NOT NULL,
       seller_id BIGINT NOT NULL,
       qty INTEGER NOT NULL CHECK (qty > 0),
       unit_price_minor BIGINT NOT NULL CHECK (unit_price_minor >= 0),
       commission_rule_id BIGINT
     );

     CREATE INDEX CONCURRENTLY orders_user_idx ON order_schema.orders(user_id, created_at DESC);

   0032_create_order_outbox.sql:
     CREATE TABLE order_schema.outbox (
       id              BIGSERIAL PRIMARY KEY,
       aggregate       TEXT NOT NULL,
       event_type      TEXT NOT NULL,
       payload         JSONB NOT NULL,
       idempotency_key TEXT NOT NULL UNIQUE,
       trace_id        TEXT,
       span_id         TEXT,
       published_at    TIMESTAMPTZ,
       created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
     );
     CREATE INDEX outbox_unpublished_idx ON order_schema.outbox(created_at) WHERE published_at IS NULL;

6. http_handler.go:
   POST /v1/orders/checkout — body {cart_id, address_id, payment_method_id}; header Idempotency-Key required.
   GET /v1/orders/{id} — auth user_id matches.
   POST /v1/orders/{id}/cancel — Idempotency-Key required.

7. Tests:
   - Concurrent checkout with same Idempotency-Key from one user → exactly one order in DB.
   - Insufficient stock → checkout fails, reservation released.
   - Saga rollback test: payment.CreateAttempt fails → no order row, no outbox row.

DO NOT cross-import any fin-svc package.
DO NOT publish events directly; only write outbox rows.
DO NOT FK across schemas.
```

**Verification / Done Criteria:**
- [ ] Concurrent checkout test produces exactly one order.
- [ ] Failed payment leaves no order row, no outbox row, releases the reservation.
- [ ] outbox row has the same idempotency_key as the order.
- [ ] No import of fin-svc packages.
- [ ] Migrations apply cleanly.

---

## Prompt 1.4 — Add catalog and order Routes to Caddyfile with Per-Endpoint Rate Limits

**Phase & Goal:** Phase 1. Expose Phase 1 endpoints through Caddy with the documented rate limits.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: PROMPTS.md Prompt 0.6, ARCHITECTURE.md § 1.

Edit /deploy/caddy/Caddyfile under the api.moproshop.com block to add four matchers + handlers for catalog, cart, orders, auth (identity).

REQUIRED MATCHERS AND LIMITS:

@auth path /v1/auth/*
handle @auth {
    rate_limit {
        zone auth_per_ip {
            key {remote_host}
            events 10
            window 1m
        }
    }
    reverse_proxy core-svc:8080
}

@catalog path /v1/products/* /v1/categories/* /v1/search
handle @catalog {
    rate_limit {
        zone catalog_per_ip {
            key {remote_host}
            events 600
            window 1m
        }
    }
    reverse_proxy core-svc:8080
}

@cart path /v1/cart/*
handle @cart {
    rate_limit {
        zone cart_per_ip {
            key {remote_host}
            events 120
            window 1m
        }
    }
    reverse_proxy core-svc:8080
}

@orders path /v1/orders/*
handle @orders {
    rate_limit {
        zone orders_per_ip {
            key {remote_host}
            events 30
            window 1m
        }
    }
    reverse_proxy core-svc:8080
}

After all module matchers, the catch-all `handle { respond 404 }` must remain LAST.

After editing:
  docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
  docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile

VERIFICATION:
  - 11th request to /v1/auth/login from the same IP within a minute returns 429.
  - 601st request to /v1/products from the same IP within a minute returns 429.
  - /v1/orders requires Authorization header; missing header returns 401 from core-svc (not from Caddy).
  - /v1/products is reachable for unauthenticated users (catalog browsing public).

DO NOT add a catch-all reverse_proxy that swallows undefined routes.
DO NOT lower the auth rate limit below 10/min — that is the bot threshold the team agreed on.
DO NOT raise the orders rate limit; checkout abuse is a real fraud vector.
```

**Verification / Done Criteria:**
- [ ] `caddy validate` passes.
- [ ] `caddy reload` succeeds with zero connection drops.
- [ ] Synthetic 11th /v1/auth/* request from one IP returns 429.
- [ ] Public catalog endpoint returns data without auth.
- [ ] Default 404 still returned for unmapped paths.

---

# PHASE 2 — FinTech Core & Ledger

The goal of Phase 2 is to bring the wallet, commission, and treasury modules online inside fin-svc, including the chart of accounts seeding, withdrawal flow, and hourly reconciliation.

## Prompt 2.1 — Create wallet Module in fin-svc with Chart of Accounts Seed

**Phase & Goal:** Phase 2. The wallet module owns the ledger; this prompt seeds the chart of accounts and exposes safe internal/private read APIs.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: LEDGER_GUIDE.md (entire), CLAUDE.md § 4, DATA_DICTIONARY.md § 2.2.

Create the wallet module inside fin-svc. It is the only module that writes to wallet_schema.ledger_entries.

PATHS:

/internal/wallet/api.go
/internal/wallet/service.go
/internal/wallet/repository.go
/internal/wallet/domain.go
/internal/wallet/errors.go
/internal/wallet/http_handler.go
/internal/wallet/{api,service}_test.go
/internal/wallet/property_test.go
/migrations/ledger/0010_seed_chart_of_accounts.sql
/migrations/ledger/0011_create_balance_view.sql

REQUIREMENTS:

1. domain.go:
   type Account struct { ID int64; Type string; OwnerType, OwnerID *int64; Currency string; Status string; CreatedAt time.Time }
   type Transaction struct { ID int64; Type string; Reference *string; IdempotencyKey string; Status string; CreatedAt time.Time }
   type Entry struct { ID int64; TransactionID int64; AccountID int64; Direction string; AmountMinor int64; CreatedAt time.Time }

2. errors.go:
   ErrIdempotencyKeyRequired, ErrInvalidAmount, ErrAccountNotFound,
   ErrAccountClosed, ErrInsufficientBalance, ErrDuplicateIdempotency,
   ErrLedgerInvariantViolation (wraps the Postgres exception class 23514).

3. api.go:
   type Service interface {
       OpenSellerWallet(ctx, sellerID int64) (Account, error)
       GetBalance(ctx, accountID int64) (int64, error)            // returns minor units
       Apply(ctx, in ApplyInput) (Transaction, error)             // generic D/C poster
       PostCommissionRefund(ctx, in CommissionRefundInput) (Transaction, error)
       PostWithdrawalReservation(ctx, in WithdrawInput) (Transaction, error)
       PostWithdrawalCompleted(ctx, ref string, idemKey string) (Transaction, error)
       PostReversal(ctx, originalTxnID int64, idemKey string) (Transaction, error)
   }

4. service.go: every public write follows the LEDGER_GUIDE.md § 6 mandatory pattern verbatim. Reuse the snippet for ApplyCommissionRefund.

5. http_handler.go (read-only public endpoints):
   GET /v1/wallet/me/balance       → uses authenticated user's seller_id
   GET /v1/wallet/me/transactions  → cursor-based pagination

   Caching: Redis SETEX wallet_balance:{account_id}, 5–10 sec TTL on GET balance. NEVER cache during a write critical path (withdraw).

6. Migrations:

   0010_seed_chart_of_accounts.sql:
     INSERT INTO wallet_schema.accounts (type, owner_type, currency)
     VALUES
       ('asset:bank:escrow',          'platform', 'TRY_COIN'),
       ('liability:platform_pool',    'platform', 'TRY_COIN'),
       ('liability:bank_outbound',    'platform', 'TRY_COIN'),
       ('equity:retained_float_income','platform','TRY_COIN')
     ON CONFLICT DO NOTHING;

   Per-seller wallet accounts are created on demand via OpenSellerWallet.

   0011_create_balance_view.sql:
     CREATE MATERIALIZED VIEW wallet_schema.balances AS
       SELECT account_id,
              SUM(CASE WHEN direction='C' THEN amount_minor ELSE -amount_minor END) AS balance_minor
       FROM wallet_schema.ledger_entries
       GROUP BY account_id;
     CREATE UNIQUE INDEX balances_account_idx ON wallet_schema.balances(account_id);
     -- REFRESH MATERIALIZED VIEW CONCURRENTLY wallet_schema.balances; in a periodic worker (Phase 3).

7. Tests:
   - service_test.go: idempotency_key replay (same input twice → one transaction).
   - service_test.go: amount_minor <= 0 → ErrInvalidAmount.
   - property_test.go (gopter): generate 1000 random ops; after applying, sum(D)-sum(C)=0.
   - integration test: imbalance attempt → repository returns ErrLedgerInvariantViolation (sees Postgres 23514).

DO NOT expose write endpoints publicly (no HTTP POST that posts to ledger).
DO NOT bypass outbox.
DO NOT use float types.
DO NOT grant wallet_user UPDATE/DELETE on ledger_entries (RULES already block it).

When done:
  go test ./internal/wallet/...
  go test -tags=integration ./internal/wallet/...
  golangci-lint run ./internal/wallet/...
```

**Verification / Done Criteria:**
- [ ] gopter property test runs ≥ 1000 successful cases.
- [ ] An imbalance attempt produces ErrLedgerInvariantViolation with Postgres ERRCODE 23514.
- [ ] Idempotency replay returns the original transaction without duplicating ledger entries.
- [ ] Materialized view returns correct balance for an account after a sequence of writes.
- [ ] No public HTTP route posts to the ledger.

---

## Prompt 2.2 — Implement Wallet Withdrawal Request (Full Saga Slice)

**Phase & Goal:** Phase 2. The withdrawal flow is the strictest financial path: reserve from seller wallet via D/C entries, write outbox, later release to actual bank transfer. This prompt implements the request side. The completion side is wired in Phase 3.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: LEDGER_GUIDE.md § 6, § 7 reversal rule, § 11 withdraw critical path; CLAUDE.md § 4.

Implement WithdrawalRequest in fin-svc/internal/wallet.

REQUIREMENTS:

1. /internal/wallet/withdraw.go contains:

   type WithdrawInput struct {
       SellerID            int64
       AmountMinor         int64
       BankAccountRef      string   // pre-validated, encrypted at rest
       IdempotencyKey      string
       UserStepUpVerifiedAt time.Time
   }

   func (s *service) PostWithdrawalReservation(ctx context.Context, in WithdrawInput) (Transaction, error) {
       if in.IdempotencyKey == "" { return Transaction{}, ErrIdempotencyKeyRequired }
       if in.AmountMinor <= 0 { return Transaction{}, ErrInvalidAmount }
       if time.Since(in.UserStepUpVerifiedAt) > 10*time.Minute {
           return Transaction{}, ErrStepUpExpired
       }

       sellerWalletID, err := s.repo.FindSellerWalletAccountID(ctx, in.SellerID)
       if err != nil { return Transaction{}, err }
       bankOutboundID := s.cfg.BankOutboundAccountID

       var txn Transaction
       err = s.repo.WithTx(ctx, sql.LevelSerializable, func(tx pgx.Tx) error {
           // Lock the seller wallet row to serialize concurrent withdraws.
           if err := s.repo.LockAccountRow(ctx, tx, sellerWalletID); err != nil { return err }

           // Solvency check (using the materialized view OR live SUM)
           bal, err := s.repo.BalanceOfTx(ctx, tx, sellerWalletID)
           if err != nil { return err }
           if bal < in.AmountMinor { return ErrInsufficientBalance }

           txnID, err := s.repo.InsertTransaction(ctx, tx, Transaction{
               Type: "withdraw_reservation",
               Reference: &in.BankAccountRef,
               IdempotencyKey: in.IdempotencyKey,
           })
           if errors.Is(err, ErrDuplicateIdempotency) { return nil }
           if err != nil { return err }

           // DEBIT seller wallet, CREDIT bank_outbound
           if err := s.repo.InsertEntry(ctx, tx, Entry{TransactionID: txnID, AccountID: sellerWalletID, Direction: "D", AmountMinor: in.AmountMinor}); err != nil { return err }
           if err := s.repo.InsertEntry(ctx, tx, Entry{TransactionID: txnID, AccountID: bankOutboundID, Direction: "C", AmountMinor: in.AmountMinor}); err != nil { return err }

           // Outbox event: fin.withdraw.requested.v1
           if err := s.outbox.Insert(ctx, tx, outbox.Row{
               Aggregate:      "wallet",
               EventType:      eventbus.TopicWithdrawRequestedV1,
               Payload:        marshalWithdrawPayload(txnID, in),
               IdempotencyKey: in.IdempotencyKey,
               TraceID:        traceIDFromCtx(ctx),
               SpanID:         spanIDFromCtx(ctx),
           }); err != nil { return err }

           txn = Transaction{ID: txnID, Type: "withdraw_reservation", IdempotencyKey: in.IdempotencyKey, Status: "posted"}
           return nil
       })
       if err != nil { return Transaction{}, err }
       return txn, nil
   }

   FindSellerWalletAccountID returns the account row for liability:wallet:seller_<id>.
   LockAccountRow runs SELECT id FROM wallet_schema.accounts WHERE id=$1 FOR UPDATE.
   BalanceOfTx is a SELECT inside the tx to ensure consistency.

2. Add a public HTTP endpoint:

   POST /v1/wallet/withdraw
     Headers: Authorization, Idempotency-Key, X-Step-Up-Token
     Body: { amount_minor, bank_account_ref }

   The handler:
     - Validates step-up token via identity service (in-memory call only inside core-svc; from fin-svc, validate via shared JWT signing key).
     - Calls PostWithdrawalReservation.
     - Returns 201 with txn id and status "pending_bank_transfer".

3. Caddyfile patch:

   @withdraw path /v1/wallet/withdraw
   handle @withdraw {
       rate_limit {
           zone withdraw_per_ip {
               key {remote_host}
               events 5
               window 1m
           }
       }
       reverse_proxy fin-svc:8080
   }

4. Tests:
   - Concurrent withdraw with same Idempotency-Key → exactly one ledger entry pair.
   - Concurrent withdraw with DIFFERENT Idempotency-Keys for the SAME seller exceeding balance → only the first succeeds; the rest get ErrInsufficientBalance.
   - Property test: 1000 random withdraws; sum(D)=sum(C) holds.

5. Caddy reload after edit.

6. mopro CLI command `mopro outbox list --aggregate wallet --since "1h"` shows the new event.

DO NOT release funds without a separate completion event (Phase 3 emits fin.withdraw.completed.v1).
DO NOT skip the SELECT FOR UPDATE on the seller wallet row.
DO NOT cache balance during the withdraw critical path.
DO NOT log bank_account_ref in plaintext.
```

**Verification / Done Criteria:**
- [ ] Concurrent withdraw with same Idempotency-Key produces exactly one transaction.
- [ ] Concurrent withdraw with different keys exceeding balance: only the first succeeds.
- [ ] outbox row created in same DB tx as ledger entries.
- [ ] Caddy rate limit caps withdraw requests at 5/minute per IP.
- [ ] gopter property test passes after withdraw integration.
- [ ] Step-up token older than 10 minutes is rejected.

---

## Prompt 2.3 — Hourly Reconciliation Cron Job

**Phase & Goal:** Phase 2. Schedule the hourly ledger invariant check that pages on-call and switches fin-svc to read-only on any non-zero delta.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: LEDGER_GUIDE.md § 8.2, DISASTER_RECOVERY.md § 2.

Implement the hourly reconciliation script and wire it.

PATHS TO TOUCH:

/scripts/ledger-reconcile.sh    # complete bash file
/cmd/fin-svc/main.go            # add a /admin/set-read-only endpoint (auth: shared static admin token)
/internal/wallet/admin.go       # SetReadOnly(reason string) function
/deploy/cron/mopro-cron         # cron file mounted into the host or a sidecar

CONTENT REQUIREMENTS:

1. /scripts/ledger-reconcile.sh — verbatim from LEDGER_GUIDE.md § 8.2:

   #!/usr/bin/env bash
   set -euo pipefail

   DIFF=$(docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -tAc \
     "SELECT COALESCE(SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END), 0)
      FROM wallet_schema.ledger_entries")

   if [ "$DIFF" -ne "0" ]; then
       docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
         "INSERT INTO wallet_schema.ledger_alerts(severity, message, detected_at)
          VALUES ('CRITICAL', 'Sum D-C != 0 (delta=$DIFF)', now())"

       curl -X POST "$PAGERDUTY_API" -H "Content-Type: application/json" \
         -d "{\"event_action\":\"trigger\",\"payload\":{\"summary\":\"LEDGER INVARIANT VIOLATION delta=$DIFF\",\"severity\":\"critical\"}}"

       curl -X POST "http://fin-svc:8080/admin/set-read-only" \
         -H "Authorization: Bearer ${ADMIN_INTERNAL_TOKEN}" \
         -d "{\"reason\":\"ledger-invariant\"}"
   fi

   curl -sf "https://hc-ping.com/$HEALTHCHECK_LEDGER_RECONCILE_UUID"

2. /cmd/fin-svc/main.go: add admin sub-router with a single handler that calls wallet.SetReadOnly.

3. /internal/wallet/admin.go:
   - SetReadOnly flips an in-memory atomic flag and writes to wallet_schema.ledger_alerts.
   - All write methods on Service check the flag and return ErrReadOnlyMode if set.
   - UnsetReadOnly is human-only via mopro CLI; not auto.

4. /deploy/cron/mopro-cron (host crontab fragment):
   5 * * * * /opt/mopro/scripts/ledger-reconcile.sh >> /var/log/mopro/reconcile.log 2>&1

5. mopro CLI command:
   mopro ledger reconcile --dry-run
   mopro ledger reconcile --confirm
   The CLI shells out to the same script for "--confirm"; for "--dry-run" it just prints DIFF without alerting.

6. Tests:
   - Manual sabotage: insert a single D entry that bypasses the trigger via raw SQL as ledger_admin (a privileged DBA action) — the reconcile script SHOULD detect it and trigger PagerDuty + read-only.
   - Healthchecks.io ping is required even when DIFF=0 (silence = alarm).

DO NOT auto-recover from a non-zero diff. Only humans flip back to read-write after investigation.
DO NOT log ADMIN_INTERNAL_TOKEN.
```

**Verification / Done Criteria:**
- [ ] Cron entry in place; first run after install logs success.
- [ ] Manual diff sabotage triggers PagerDuty test (use a non-prod webhook in dev).
- [ ] fin-svc switches to read-only after the script's POST.
- [ ] All wallet writes return ErrReadOnlyMode while in read-only.
- [ ] Healthchecks.io ping fires even on DIFF=0.

---

## Prompt 2.4 — commission Settlement Cron and Accrual Path

**Phase & Goal:** Phase 2. Implement the monthly commission settlement that computes accrued amounts per seller and emits fin.commission.refund_requested.v1, plus the consumer that posts the actual ledger entries.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: ARCHITECTURE.md § 5 step 7–10, LEDGER_GUIDE.md § 6, eventbus topics.

Implement the commission module accrual + settlement.

PATHS:

/internal/commission/api.go
/internal/commission/service.go
/internal/commission/accrual.go
/internal/commission/settlement.go
/internal/commission/repository.go
/internal/commission/domain.go
/internal/commission/{api,service,settlement}_test.go
/migrations/ledger/0020_create_commission_tables.sql
/scripts/settlement-monthly.sh

REQUIREMENTS:

1. domain.go:
   type Rule struct { ID int64; CategoryID int64; Percent int32; Active bool }   // percent in basis points (e.g., 250 = 2.5%)
   type Accrual struct { ID int64; OrderID int64; SellerID int64; AmountMinor int64; Period string; CreatedAt time.Time }
   type Settlement struct { ID int64; SellerID int64; Period string; AmountMinor int64; Status string; CreatedAt time.Time }

2. 0020_create_commission_tables.sql:
   CREATE TABLE commission_schema.rules (
       id BIGSERIAL PRIMARY KEY, category_id BIGINT NOT NULL, percent INTEGER NOT NULL CHECK (percent BETWEEN 0 AND 5000),
       active BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
   );
   CREATE TABLE commission_schema.accruals (
       id BIGSERIAL PRIMARY KEY, order_id BIGINT NOT NULL, seller_id BIGINT NOT NULL,
       amount_minor BIGINT NOT NULL CHECK (amount_minor > 0), period TEXT NOT NULL,
       idempotency_key TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
   );
   CREATE INDEX accruals_period_seller_idx ON commission_schema.accruals(period, seller_id);
   CREATE TABLE commission_schema.settlements (
       id BIGSERIAL PRIMARY KEY, seller_id BIGINT NOT NULL, period TEXT NOT NULL,
       amount_minor BIGINT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
       idempotency_key TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
   );

3. accrual.go consumer for ecom.order.completed.v1:
   - On each event, compute commission per item using rules, insert one accruals row per (order_id, seller_id, period). idempotency_key = `accrual:${order_id}:${seller_id}`.
   - The accrual itself does NOT post ledger entries; it accumulates obligations.

4. settlement.go is the cron-triggered function:

   func (s *service) RunSettlement(ctx context.Context, period string) error {
       // 1. Aggregate accruals per seller for the period.
       // 2. For each seller with > 0 accrued, insert a settlement row + emit fin.commission.refund_requested.v1 via outbox.
       // 3. Mark accruals as settled (a status column is added in a later migration if needed).
   }

5. wallet consumer for fin.commission.refund_requested.v1:
   - Posts ledger entries: D liability:platform_pool, C liability:wallet:seller_<id>, amount_minor.
   - Idempotency: settlement.idempotency_key.
   - Emits fin.commission.refund_posted.v1 via outbox.

6. /scripts/settlement-monthly.sh:
   #!/usr/bin/env bash
   set -euo pipefail
   PERIOD=$(date -u -d "yesterday" +%Y-%m)
   docker exec fin-svc /app/app run-settlement --period "$PERIOD"

7. Cron: 0 3 1 * * /opt/mopro/scripts/settlement-monthly.sh >> /var/log/mopro/settlement.log 2>&1

8. Tests:
   - Run-settlement twice for the same period → exactly one settlement row per seller (idempotent).
   - Property test: total accruals = total settlements (per period, per seller, per amount).

DO NOT post commission ledger entries directly from the order.completed consumer; only accruals there.
DO NOT use float for percent calculations; use integer math with basis points.
```

**Verification / Done Criteria:**
- [ ] accrual consumer is idempotent across replays.
- [ ] Settlement cron is idempotent across same-period runs.
- [ ] After settlement, ledger entries appear with correct D/C and balance.
- [ ] fin.commission.refund_posted.v1 events appear in Redis Streams.
- [ ] No floats anywhere.

---

# PHASE 3 — Distributed Sagas & Async Jobs

The goal of Phase 3 is to wire the cross-service async flows: Redis Streams consumers, DLQ handling, retries, and the outbox-publisher worker.

## Prompt 3.1 — Wire `ecom.order.completed.v1` Saga End-to-End

**Phase & Goal:** Phase 3. Connect order-side outbox publication to fin-svc commission accrual consumption and jobs-svc notification dispatch.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: ARCHITECTURE.md § 5, eventbus internals, LEDGER_GUIDE.md outbox rules.

Wire the `ecom.order.completed.v1` topic from production to consumption.

PRODUCER SIDE (core-svc):

1. /internal/payment/captured_listener.go:
   When the PSP webhook reports payment.captured for an order:
   - Begin postgres-ecom tx.
   - UPDATE order_schema.orders SET status='paid' WHERE id=$1 AND status='pending_payment'.
   - INSERT INTO order_schema.outbox VALUES (event_type='ecom.order.completed.v1', payload, idempotency_key=order_id::text).
   - Commit.

2. /internal/order/outbox_publisher.go:
   Reuse internal/outbox.Publisher pointed at order_schema.outbox. Worker started in /cmd/core-svc/main.go.

CONSUMER SIDE (fin-svc):

3. /internal/commission/accrual_consumer.go:
   group: "fin-commission"
   consumer: hostname or container ID
   On message: parse payload, compute commission per item, write accrual rows; idempotency via accruals.idempotency_key.
   On success: XACK.
   On error after 5 retries: DLQ (see Prompt 3.2).

CONSUMER SIDE (jobs-svc):

4. /internal/notification/order_completed_listener.go:
   group: "jobs-notification"
   On message: enqueue an SMS + push notification for the user. Idempotency: notification.id derived from event.idempotency_key.

WIRING:

5. /cmd/core-svc/main.go starts the publisher worker.
   /cmd/fin-svc/main.go starts the accrual consumer.
   /cmd/jobs-svc/main.go starts the notification consumer.

6. Tracing:
   Each consumer creates a child span from the trace_id in the event. Spans are exported to Grafana Tempo via OTLP.

7. Tests (integration):
   - Place an order, simulate payment.captured.
   - Verify: order status=paid, outbox row published_at set, commission accrual row exists, notification queued.
   - End-to-end: a single trace_id appears in all three services' logs.

DO NOT auto-bridge the consumer with `if err == nil`; you MUST XACK only after Handler returns nil; on error, do not XACK so it stays in PEL for XCLAIM.
DO NOT have multiple consumer groups for the same service+topic combination.
DO NOT inline the consumer's handler logic into the eventbus; keep separation.
```

**Verification / Done Criteria:**
- [ ] After a simulated payment.captured, the order is paid, accrual exists, notification queued.
- [ ] One trace_id is present across producer + both consumers.
- [ ] Replaying the same event N times yields one accrual and one notification.
- [ ] XPENDING on the consumer group is empty after success.

---

## Prompt 3.2 — DLQ Handling for Failed Consumer

**Phase & Goal:** Phase 3. Failures must not block the stream; after N retries an event lands in a DLQ stream for human inspection.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: eventbus.RedisBus, eventbus.DLQ.

Implement the per-topic DLQ.

REQUIREMENTS:

1. /internal/eventbus/dlq.go RedisDLQ:
   - For topic T, DLQ stream is `<T>.dlq`.
   - Push records: {event_id, original_payload, first_failed_at, last_failed_at, failure_count, last_error, consumer_group}.
   - MAXLEN ~ 5000 (approx) to bound storage.

2. RedisBus.Run loop:
   On handler error:
     - Increment per-message retry counter in a hash key: pel:{group}:{message_id}.
     - If retries < 5: do nothing (message remains in PEL; XCLAIM will retry after pendingTimeout).
     - If retries == 5: dlq.Push, then XACK to clear the PEL entry.
   - Use XCLAIM with idleTime=pendingTimeout (default 60s) to reclaim stuck messages from dead consumers.

3. mopro CLI:
   mopro outbox list --aggregate <name>                    # in DB outbox
   mopro stream dlq list <topic>                           # show DLQ entries
   mopro stream dlq replay <topic> --event-id <id>         # republish to original topic with idempotency_key preserved
   mopro stream dlq purge <topic> --before "2025-01-01"

4. Metrics:
   mopro_eventbus_consumer_failures_total{topic,group,reason}
   mopro_eventbus_dlq_pushes_total{topic}
   mopro_eventbus_dlq_size{topic}    # gauge sampled every 30s

5. Alerts:
   - dlq_size > 10 → Slack alert.
   - dlq_size > 100 → PagerDuty.

6. Tests:
   - Failing handler: after 5 retries, event lands on DLQ; further events on the topic still process.
   - Reclaim: kill the consumer mid-handle; another consumer in the group picks up after pendingTimeout.

DO NOT auto-replay from DLQ. Replay is a human decision via mopro CLI.
DO NOT XACK before handler success.
```

**Verification / Done Criteria:**
- [ ] Permanently-failing handler routes the event to DLQ after 5 retries.
- [ ] Other events on the same topic continue to process.
- [ ] mopro stream dlq list shows the failed event.
- [ ] PagerDuty alert wires fire on dlq_size > 100.

---

## Prompt 3.3 — outbox-publisher Worker Shipping Daemon

**Phase & Goal:** Phase 3. Final hardening of the outbox-publisher to handle backpressure, monitoring, and graceful shutdown.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: /internal/outbox/publisher.go (existing skeleton), eventbus.Publisher.

Productionize the outbox-publisher.

REQUIREMENTS:

1. Backpressure:
   - If bus.Publish returns error for > 1 minute consecutively, slow down poll interval from 250 ms to 5 s.
   - Recovery: as soon as one Publish succeeds, return to 250 ms.

2. Metrics:
   mopro_outbox_pending_count{aggregate}        # gauge
   mopro_outbox_publish_total{aggregate,result} # counter
   mopro_outbox_publish_latency_ms{aggregate}   # histogram

3. Graceful shutdown:
   - On SIGTERM: stop the polling loop, drain in-flight publishes (max 30 s), close DB pool.

4. Multi-instance safety:
   Use SELECT ... FROM <schema>.outbox WHERE published_at IS NULL ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED.
   This allows multiple publishers to coexist without double-publishing.

5. Per-aggregate publishers:
   core-svc runs publishers for order_schema.outbox, identity_schema.outbox (when added).
   fin-svc runs publishers for wallet_schema.outbox, commission_schema.outbox.
   Each is a separate goroutine with its own SELECT scope.

6. Health endpoint:
   GET /healthz/outbox returns {pending:<count>, oldest:<rfc3339>, lag_seconds:<int>}.

7. Tests:
   - Insert 10000 outbox rows; publisher empties them in < 60 s.
   - Kill publisher mid-batch; a second instance picks up via SKIP LOCKED.
   - Publish failure for 65 s → poll interval slows to 5 s.

DO NOT publish a row twice (idempotency_key on bus side, but also UPDATE SET published_at upon success).
DO NOT delete outbox rows; keep them for audit. A separate weekly job archives older-than-90-days rows.
```

**Verification / Done Criteria:**
- [ ] 10k row drain in < 60 s.
- [ ] Two publisher processes do not double-publish.
- [ ] Backpressure activates and deactivates correctly.
- [ ] /healthz/outbox lag matches reality.

---

# PHASE 4 — Flutter Mobile App

The goal of Phase 4 is to build the Flutter mobile app skeleton with Riverpod 2 + code generation, Dio with interceptors, and atomic-design widgets. The Wallet Summary widget below is the template; cart, catalog, etc. follow the same pattern.

## Prompt 4.1 — Initialize Flutter Project with Riverpod 2 + Generator

**Phase & Goal:** Phase 4. Bootstrap the mobile project with the chosen state management and code-generation toolchain.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: PRD v3.2 § 5 (Mobile Application Architecture).

Initialize a Flutter app at /mobile/.

REQUIREMENTS:

1. Run: flutter create --org com.mopro --project-name mopro_shop mobile/
2. /mobile/pubspec.yaml dependencies (latest stable as of 2026):

   dependencies:
     flutter: { sdk: flutter }
     flutter_riverpod: ^2.5.1
     riverpod_annotation: ^2.3.5
     dio: ^5.5.0
     retrofit: ^4.4.1
     cached_network_image: ^3.4.1
     flutter_secure_storage: ^9.2.2
     freezed_annotation: ^2.4.4
     json_annotation: ^4.9.0
     uuid: ^4.5.1
     sentry_flutter: ^8.10.0
     firebase_messaging: ^15.1.4
     firebase_core: ^3.8.0
     mixpanel_flutter: ^2.3.4
     isar: ^3.1.0
     isar_flutter_libs: ^3.1.0

   dev_dependencies:
     flutter_test: { sdk: flutter }
     build_runner: ^2.4.13
     riverpod_generator: ^2.4.3
     freezed: ^2.5.7
     json_serializable: ^6.8.0
     retrofit_generator: ^9.1.5
     custom_lint: ^0.6.4
     riverpod_lint: ^2.3.13
     mocktail: ^1.0.4

3. Folder structure:
   /mobile/lib/
     main.dart
     app.dart
     core/
       config/
       errors/
       network/             # dio, interceptors, retrofit clients
       storage/             # secure storage wrappers
       analytics/
     features/
       auth/
       home/
       catalog/
       cart/
       wallet/
       support/
       profile/
     shared/
       atoms/
       molecules/
       organisms/
       theme/

4. Riverpod root in main.dart:
   void main() {
     WidgetsFlutterBinding.ensureInitialized();
     runZonedGuarded(() {
       runApp(const ProviderScope(child: MoproApp()));
     }, (e, s) => /* sentry capture */);
   }

5. Code generation working:
   dart pub get
   dart run build_runner build --delete-conflicting-outputs

6. Smoke test:
   flutter test
   flutter analyze

7. iOS/Android baseline:
   - Set min iOS to 13.0, min Android API to 23.
   - Add release signing config placeholders (no real keys committed).

DO NOT use any state management other than Riverpod 2.
DO NOT use http package; only Dio.
DO NOT include firebase_messaging without firebase_core (init order).
DO NOT commit GoogleService-Info.plist or google-services.json (gitignore them).
```

**Verification / Done Criteria:**
- [ ] `flutter pub get` succeeds.
- [ ] `dart run build_runner build` succeeds.
- [ ] `flutter test` and `flutter analyze` are green.
- [ ] No firebase config files committed.
- [ ] App runs on iOS simulator and Android emulator (`flutter run`).

---

## Prompt 4.2 — Build Dio Client with Interceptors (Auth, Idempotency, Trace, Retry)

**Phase & Goal:** Phase 4. Every API call must carry a fresh Idempotency-Key for mutations, propagate trace_id for observability, attach the bearer token, and retry idempotent failures.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: PRD v3.2 § 12 API design, DEVELOPMENT.md.

Implement the network stack.

PATHS:

/mobile/lib/core/network/dio_factory.dart
/mobile/lib/core/network/interceptors/auth_interceptor.dart
/mobile/lib/core/network/interceptors/idempotency_interceptor.dart
/mobile/lib/core/network/interceptors/trace_interceptor.dart
/mobile/lib/core/network/interceptors/retry_interceptor.dart
/mobile/lib/core/network/interceptors/error_interceptor.dart
/mobile/lib/core/network/api_client.dart           # @RestApi() retrofit client
/mobile/lib/core/storage/secure_storage.dart
/mobile/lib/core/network/network_test.dart

REQUIREMENTS:

1. dio_factory.dart:
   Dio buildDio({required String baseUrl}) {
     final dio = Dio(BaseOptions(
       baseUrl: baseUrl,
       connectTimeout: const Duration(seconds: 6),
       receiveTimeout: const Duration(seconds: 12),
       sendTimeout:    const Duration(seconds: 6),
       headers: { 'Accept': 'application/json' },
     ));
     dio.interceptors.addAll([
       TraceInterceptor(),
       AuthInterceptor(secureStorage),
       IdempotencyInterceptor(),
       RetryInterceptor(),
       ErrorInterceptor(sentry),
     ]);
     return dio;
   }

2. trace_interceptor.dart:
   - On request: attach `X-Trace-ID: <uuid v4>` if absent.
   - On response: read `X-Trace-ID` from server (if echoed) for log correlation.

3. auth_interceptor.dart:
   - Attach `Authorization: Bearer <jwt>` from secure storage.
   - On 401 response: try refresh once via /v1/auth/refresh; on success, retry the original request.
   - On second 401: clear tokens, push to login screen.

4. idempotency_interceptor.dart:
   - For methods POST, PUT, PATCH, DELETE: generate a UUID v4 and attach `Idempotency-Key`.
   - Cache the (URL + body hash → key) mapping in-memory for 24 h so retries reuse the same key.

5. retry_interceptor.dart:
   - Retry up to 3 times for 5xx, network errors, 429.
   - Exponential backoff: 200 ms, 600 ms, 1.2 s with jitter.
   - DO NOT retry POST/PATCH/DELETE without an Idempotency-Key.

6. error_interceptor.dart:
   - Map HTTP errors to typed exceptions in /core/errors/.
   - Forward to Sentry with breadcrumbs (URL, status, trace_id; NEVER body content).

7. api_client.dart with retrofit:
   @RestApi(baseUrl: '')
   abstract class ApiClient {
     factory ApiClient(Dio dio) = _ApiClient;

     @GET('/v1/wallet/me/balance')
     Future<WalletBalanceDto> walletBalance();

     @POST('/v1/orders/checkout')
     Future<CheckoutResponseDto> checkout(@Body() CheckoutRequestDto body);
   }

8. Tests with mocktail:
   - 401 → refresh → retry happy path.
   - 5xx → 3 retries → final failure surfaces typed exception.
   - POST without explicit Idempotency-Key → interceptor adds one.
   - Same logical request retried → same Idempotency-Key reused for 24 h.

DO NOT log request/response bodies in production builds.
DO NOT store tokens in SharedPreferences; only flutter_secure_storage.
DO NOT swallow exceptions silently.
```

**Verification / Done Criteria:**
- [ ] Tests for refresh, retry, idempotency-key cache pass.
- [ ] Sentry captures errors with trace_id but never body content.
- [ ] Retrofit client compiles after `build_runner build`.

---

## Prompt 4.3 — Wallet Summary Widget Following Atomic Design

**Phase & Goal:** Phase 4. Build the mobile Wallet feature: data layer (provider, repository), presentation layer (atom→molecule→organism), with the Wallet Summary widget on the Home/Wallet screen.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: PRD v3.2 § 6.5 (Wallet flows), Prompt 4.2.

Build the Wallet Summary feature.

PATHS:

/mobile/lib/features/wallet/data/wallet_dto.dart
/mobile/lib/features/wallet/data/wallet_repository.dart
/mobile/lib/features/wallet/data/wallet_repository_impl.dart
/mobile/lib/features/wallet/application/wallet_provider.dart    # @riverpod
/mobile/lib/features/wallet/presentation/wallet_summary_card.dart
/mobile/lib/features/wallet/presentation/wallet_screen.dart
/mobile/lib/shared/atoms/mopro_text.dart
/mobile/lib/shared/atoms/mopro_button.dart
/mobile/lib/shared/atoms/mopro_skeleton.dart
/mobile/lib/shared/molecules/balance_chip.dart
/mobile/lib/shared/organisms/transaction_list.dart
/mobile/lib/shared/theme/mopro_theme.dart
/mobile/test/features/wallet/wallet_provider_test.dart

REQUIREMENTS:

1. wallet_dto.dart with Freezed:
   @freezed
   class WalletBalanceDto with _$WalletBalanceDto {
     const factory WalletBalanceDto({
       required int balanceMinor,    // amount in minor units
       required String currency,     // 'TRY_COIN'
       required DateTime asOf,
     }) = _WalletBalanceDto;

     factory WalletBalanceDto.fromJson(Map<String, dynamic> json) =>
         _$WalletBalanceDtoFromJson(json);
   }

2. wallet_repository.dart:
   abstract class WalletRepository {
     Future<WalletBalanceDto> getBalance();
     Future<List<WalletTransactionDto>> listTransactions({String? cursor});
     Future<WithdrawResponseDto> requestWithdraw({
       required int amountMinor,
       required String bankAccountRef,
       required String stepUpToken,
     });
   }

3. wallet_repository_impl.dart uses ApiClient (Prompt 4.2).
   - getBalance: GET /v1/wallet/me/balance.
   - listTransactions: GET /v1/wallet/me/transactions?after=<cursor>.
   - requestWithdraw: POST /v1/wallet/withdraw with X-Step-Up-Token.

4. wallet_provider.dart with riverpod_generator:
   @riverpod
   Future<WalletBalanceDto> walletBalance(WalletBalanceRef ref) async {
     final repo = ref.watch(walletRepositoryProvider);
     return repo.getBalance();
   }

   @riverpod
   class WalletNotifier extends _$WalletNotifier {
     @override
     FutureOr<WalletBalanceDto> build() async {
       final repo = ref.watch(walletRepositoryProvider);
       return repo.getBalance();
     }
     Future<void> refresh() async {
       state = const AsyncValue.loading();
       state = await AsyncValue.guard(() => ref.read(walletRepositoryProvider).getBalance());
     }
   }

5. atoms (mopro_text, mopro_button, mopro_skeleton):
   - Use only ThemeExtension tokens; no hardcoded colors.
   - mopro_skeleton renders a shimmer placeholder.

6. molecule balance_chip.dart:
   - Pill-shaped chip with formatted amount + currency.
   - Format: minor → human ("12.345,67 TL"). Use intl.

7. organism transaction_list.dart:
   - Paginated list with pull-to-refresh.
   - Empty state, error state, loading skeletons.

8. wallet_summary_card.dart:
   - Big balance + "Withdraw" button + recent 3 transactions.
   - Wraps balance_chip and a small transaction_list slice.
   - Listens to walletNotifierProvider; on AsyncLoading shows skeletons; on AsyncError shows retry button.

9. wallet_screen.dart:
   - Pull-to-refresh.
   - Withdraw button → opens a bottom sheet with amount input + bank account picker; after step-up auth (biometric or OTP modal), calls requestWithdraw with a fresh Idempotency-Key (handled by the Dio interceptor).

10. mopro_theme.dart:
    - Define ThemeExtension<MoproColors> with primary, surface, onSurface, success, danger, warning.
    - Define ThemeExtension<MoproRadii>, ThemeExtension<MoproSpacing>.

11. wallet_provider_test.dart with mocktail:
    - Initial state: AsyncValue.loading.
    - Success: emits AsyncData with balance.
    - Network error: emits AsyncError; refresh() recovers.

DO NOT hardcode colors, paddings, or text styles in atoms; use ThemeExtension.
DO NOT format money with toString(); always use intl.NumberFormat with locale.
DO NOT call repository directly from a Widget; always go via a provider.
```

**Verification / Done Criteria:**
- [ ] `flutter test` includes wallet_provider_test and passes.
- [ ] `flutter analyze` is clean.
- [ ] Pull-to-refresh updates the balance.
- [ ] Withdraw flow shows step-up modal before sending the request.
- [ ] Skeletons appear during initial load.
- [ ] Idempotency-Key header is present on the withdraw POST (verified by network log in dev build).

---

# PHASE 5 — Observability & Hardening

## Prompt 5.1 — Add slog + trace_id to Existing HTTP Handler

**Phase & Goal:** Phase 5. Convert any existing handler to emit structured slog logs with trace_id and span_id, and to start an OTel span propagated to downstream calls.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: INFRASTRUCTURE.md § 9 logging contract, ARCHITECTURE.md § 5 trace flow.

Add slog + OpenTelemetry tracing to the wallet GET /v1/wallet/me/balance handler. Use this work as the template; apply the same pattern to every other handler in a follow-up PR.

PATHS TO TOUCH OR CREATE:

/pkg/logger/logger.go             # initialize a process-global slog.Logger as JSON
/pkg/tracing/tracing.go           # OTel tracer init shipping to grafana-agent OTLP
/pkg/httpx/middleware.go          # mux middleware that creates a span and a request-scoped logger
/internal/wallet/http_handler.go  # use the middleware

REQUIREMENTS:

1. /pkg/logger/logger.go:
   func New(service string) *slog.Logger {
       h := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
       return slog.New(h).With(
           slog.String("service", service),
           slog.String("env", os.Getenv("ENV")),
       )
   }
   PII MUST NEVER reach the logger. The handler accepts only typed values; do not pass user-controlled strings as keys.

2. /pkg/tracing/tracing.go:
   func InitTracer(ctx context.Context, service string) (func(context.Context) error, error) {
       exp, err := otlptracegrpc.New(ctx, otlptracegrpc.WithEndpoint("grafana-agent:4317"), otlptracegrpc.WithInsecure())
       if err != nil { return nil, err }
       res, _ := resource.New(ctx, resource.WithAttributes(semconv.ServiceName(service)))
       tp := sdktrace.NewTracerProvider(
           sdktrace.WithBatcher(exp),
           sdktrace.WithResource(res),
           sdktrace.WithSampler(sdktrace.TraceIDRatioBased(1.0)),  // dev: 100%; prod: lower if needed
       )
       otel.SetTracerProvider(tp)
       otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))
       return tp.Shutdown, nil
   }

3. /pkg/httpx/middleware.go TraceAndLog middleware:
   func TraceAndLog(base *slog.Logger, tracer trace.Tracer) func(http.Handler) http.Handler {
       return func(next http.Handler) http.Handler {
           return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
               ctx, span := tracer.Start(r.Context(), r.Method + " " + r.URL.Path)
               defer span.End()

               // Trace ID propagation: prefer incoming X-Trace-ID, fall back to span ID.
               traceID := r.Header.Get("X-Trace-ID")
               if traceID == "" { traceID = span.SpanContext().TraceID().String() }

               logger := base.With(
                   slog.String("trace_id", traceID),
                   slog.String("span_id", span.SpanContext().SpanID().String()),
                   slog.String("module", chi.RouteContext(r.Context()).RoutePattern()),
                   slog.String("http_method", r.Method),
                   slog.String("http_path", r.URL.Path),
               )
               ctx = withLogger(ctx, logger)

               start := time.Now()
               rec := newStatusRecorder(w)
               next.ServeHTTP(rec, r.WithContext(ctx))

               logger.LogAttrs(ctx, slog.LevelInfo, "http_request_completed",
                   slog.Int("http_status", rec.status),
                   slog.Int64("duration_ms", time.Since(start).Milliseconds()),
               )
           })
       }
   }

4. /internal/wallet/http_handler.go:
   func (h *Handler) GetMyBalance(w http.ResponseWriter, r *http.Request) {
       ctx := r.Context()
       logger := loggerFromCtx(ctx)
       sellerID := authSellerID(r)

       balance, err := h.svc.GetBalance(ctx, h.repo.SellerWalletAccountID(sellerID))
       if err != nil {
           logger.LogAttrs(ctx, slog.LevelError, "wallet_balance_failed", slog.String("err", err.Error()))
           writeProblem(w, http.StatusInternalServerError, "/errors/internal", "internal error")
           return
       }

       logger.LogAttrs(ctx, slog.LevelInfo, "wallet_balance_served",
           slog.Int64("amount_minor", balance),    // SAFE: not PII
           slog.String("currency", "TRY_COIN"),
       )
       writeJSON(w, http.StatusOK, map[string]any{"balance_minor": balance, "currency": "TRY_COIN"})
   }

5. /cmd/fin-svc/main.go:
   shutdown, _ := tracing.InitTracer(ctx, "fin-svc")
   defer shutdown(ctx)
   logger := logger.New("fin-svc")
   r.Use(httpx.TraceAndLog(logger, otel.Tracer("fin-svc")))

6. Verify locally:
   - curl http://api.localhost/v1/wallet/me/balance with `X-Trace-ID: aaaa1111`.
   - Logs in fin-svc include trace_id=aaaa1111 in JSON form.
   - Tempo shows the span with the same trace_id.

7. PII safety:
   - Never log r.Header verbatim (Authorization leak).
   - Never log request bodies.
   - Never log seller phone/email/TC (use hashed lookup id only).

DO NOT use log.Println; only the slog.Logger.
DO NOT panic in handlers; recover middleware logs and returns 500.
```

**Verification / Done Criteria:**
- [ ] curl with X-Trace-ID propagates to logs and Tempo.
- [ ] http_request_completed log entry has trace_id, span_id, status, duration.
- [ ] No PII fields in any log entry on this path.
- [ ] Tempo waterfall shows the span with correct service name.

---

## Prompt 5.2 — disk-watch.sh with Panic Mode at 92%

**Phase & Goal:** Phase 5. Implement the disk pressure watchdog that escalates from Slack to PagerDuty to a Postgres read-only panic switch.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: DISASTER_RECOVERY.md § 2.

Create the disk watcher and wire its cron.

PATHS:

/scripts/disk-watch.sh          # full bash script (verbatim from DISASTER_RECOVERY.md § 2.2)
/scripts/disk-hygiene.sh        # weekly cron (verbatim from DISASTER_RECOVERY.md § 2.4)
/deploy/cron/disk-cron          # crontab fragment

CONTENT:

1. /scripts/disk-watch.sh:

   #!/usr/bin/env bash
   # /opt/mopro/scripts/disk-watch.sh
   # 5 dakikada bir cron ile çalışır
   set -euo pipefail
   USE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

   if [ "$USE" -ge 92 ]; then
       docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
         "ALTER SYSTEM SET default_transaction_read_only = on;" || true
       docker exec postgres-ecom psql -U ecom_admin -c "SELECT pg_reload_conf();" || true
       docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
         "ALTER SYSTEM SET default_transaction_read_only = on;" || true
       docker exec postgres-ledger psql -U ledger_admin -c "SELECT pg_reload_conf();" || true
       curl -X POST "$SLACK_PANIC_WEBHOOK" -d "{\"text\":\"PANIC: Disk %${USE} - Postgres read-only modda\"}"
   elif [ "$USE" -ge 85 ]; then
       curl -X POST "$BETTERSTACK_INCIDENT_API" -d "Disk %${USE}"
   elif [ "$USE" -ge 75 ]; then
       curl -X POST "$SLACK_WEBHOOK" -d "{\"text\":\"Uyarı: Disk %${USE} - cleanup düşün\"}"
   fi

2. /scripts/disk-hygiene.sh (weekly):

   #!/usr/bin/env bash
   # /opt/mopro/scripts/disk-hygiene.sh — Cron: 0 4 * * 1
   set -euo pipefail
   docker system prune -af --volumes
   find /var/lib/docker/containers/ -name "*.log" -size +100M -delete
   apt-get clean
   find /opt/mopro/data/postgres-ecom/pg_wal/archive_status -name "*.done" -mtime +2 -delete
   find /opt/mopro/data/postgres-ledger/pg_wal/archive_status -name "*.done" -mtime +2 -delete
   find /tmp -type f -atime +7 -delete
   echo "Disk: $(df / | awk 'NR==2 {print $5}')"
   curl -sf "https://hc-ping.com/$HEALTHCHECK_DISK_HYGIENE_UUID" || true

3. /deploy/cron/disk-cron:

   */5 * * * * /opt/mopro/scripts/disk-watch.sh >> /var/log/mopro/disk-watch.log 2>&1
   0 4 * * 1   /opt/mopro/scripts/disk-hygiene.sh >> /var/log/mopro/disk-hygiene.log 2>&1

4. Lift-off ritual after panic:
   Document in /docs/runbooks/disk-panic-recovery.md the operator steps from DISASTER_RECOVERY.md § 2.3 (run hygiene; check WAL backlog; lift read-only with ALTER SYSTEM SET default_transaction_read_only = off; SELECT pg_reload_conf()).

5. Tests:
   - Unit test (bash) using a mocked `df` that prints 92 → script issues the read-only command (use a stub `docker` shim).
   - Integration: simulate ≥ 92% by running a temporary `dd if=/dev/zero of=/var/tmp/filler bs=1M count=N` until threshold; verify Postgres goes read-only; remove filler; manually lift.

6. Permissions:
   - Scripts owned by root, mode 700.
   - `/opt/mopro/.env` referenced from scripts has chmod 600.

DO NOT auto-undo panic mode. Only humans flip back to read-write.
DO NOT delete Postgres data files.
DO NOT delete .ready WAL files.
DO NOT remove this cron when the cluster is healthy.
```

**Verification / Done Criteria:**
- [ ] Script execution with mocked 76 → Slack alert, no escalation.
- [ ] Mocked 86 → Better Stack incident.
- [ ] Mocked 93 → Postgres switches to read-only on both clusters; Slack panic webhook fires.
- [ ] After lifting read-only manually, normal writes resume.
- [ ] Cron entries scheduled and listed by `crontab -l` for root.

---

## Prompt 5.3 — Backup Pipeline + Weekly Restore Drill

**Phase & Goal:** Phase 5. Operationalize daily backups to Backblaze B2 with restic and weekly automated restore drills.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: DISASTER_RECOVERY.md § 4.

Implement backup and restore drill scripts.

PATHS:

/scripts/backup.sh
/scripts/restore-drill.sh
/deploy/cron/backup-cron

REQUIREMENTS:

1. /scripts/backup.sh (cron 0 3 * * *):

   #!/usr/bin/env bash
   set -euo pipefail
   source /opt/mopro/.env
   DATE=$(date +%Y%m%d_%H%M%S)
   WORK=/opt/mopro/backups/$DATE
   mkdir -p "$WORK"

   docker exec postgres-ecom pg_dumpall -U ecom_admin     | gzip > "$WORK/postgres-ecom.sql.gz"
   docker exec postgres-ledger pg_dumpall -U ledger_admin | gzip > "$WORK/postgres-ledger.sql.gz"

   docker exec redis redis-cli -a "$REDIS_PASSWORD" SAVE
   docker cp redis:/data/dump.rdb "$WORK/redis.rdb"

   curl -s -X POST -H "Authorization: Bearer $MEILI_MASTER_KEY" http://localhost:7700/dumps
   sleep 30
   docker cp meilisearch:/meili_data/dumps "$WORK/meilisearch_dumps"

   export RESTIC_REPOSITORY="b2:mopro-backups:/full"
   export RESTIC_PASSWORD="$RESTIC_PASSWORD"
   export B2_ACCOUNT_ID="$B2_KEY_ID"
   export B2_ACCOUNT_KEY="$B2_APP_KEY"

   restic backup --tag full --tag "$DATE" "$WORK"
   find /opt/mopro/backups -maxdepth 1 -type d -mtime +2 -exec rm -rf {} +
   restic forget --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --prune
   curl -sf "https://hc-ping.com/$HEALTHCHECK_BACKUP_UUID" || true

2. /scripts/restore-drill.sh (cron 0 4 * * 0): verbatim from DISASTER_RECOVERY.md § 4.3.

3. /deploy/cron/backup-cron:
   0 3 * * *  /opt/mopro/scripts/backup.sh        >> /var/log/mopro/backup.log 2>&1
   0 4 * * 0  /opt/mopro/scripts/restore-drill.sh >> /var/log/mopro/restore.log 2>&1

4. Tests:
   - Run backup once: a new restic snapshot appears in B2.
   - Run restore-drill once: an ephemeral postgres-test container loads the dump and the test asserts product count > 0; container is cleaned up.

5. Failure handling:
   - If backup fails, healthchecks.io NOT pinged → silence → alarm fires within 6 hours.
   - If restore drill fails, deployment freeze policy: PR merge blocked by a CI check that reads the last drill result file `/var/lib/mopro/last-drill-result`.

DO NOT keep restic password in repo. Use .env (chmod 600).
DO NOT delete B2 retention policies without an explicit human confirmation step.
```

**Verification / Done Criteria:**
- [ ] First scheduled backup creates a snapshot in B2.
- [ ] First scheduled restore drill loads a fresh Postgres container and asserts data.
- [ ] Healthchecks.io receives backup and drill pings on success.
- [ ] CI check `last-drill-result` reads `OK` after a healthy drill.

---

# PHASE 6 — Pre-Launch & Production Readiness

The goal of Phase 6 is to validate the system end-to-end at expected load, finalize launch checklists, and freeze configuration.

## Prompt 6.1 — Build the Load Testing Harness (k6) and Run a Capacity Test

**Phase & Goal:** Phase 6. Confirm the system holds at 30K users/hour (~300 RPS sustained, ~600 RPS bursts) with cache hit rates and DB QPS within budget.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: PRD v3.2 § 13 capacity model.

Build a k6 load-test harness.

PATHS:

/loadtest/k6/scenarios.js
/loadtest/k6/lib/auth.js
/loadtest/k6/lib/cart.js
/loadtest/k6/lib/checkout.js
/loadtest/k6/run.sh

REQUIREMENTS:

1. scenarios.js: emulate the Phase-2 traffic mix:
   - 45% home/feed reads
   - 20% catalog browse + search
   - 15% product detail
   - 5% cart writes
   - 3% checkout (POST /v1/orders/checkout with Idempotency-Key)
   - 2% wallet balance read
   - 10% misc

2. Stages (export const options):
   - 0 → 100 VUs over 2 minutes (warm up)
   - hold 100 VUs for 10 minutes (steady)
   - ramp to 300 VUs over 2 minutes
   - hold 300 VUs for 5 minutes
   - drain to 0 VUs over 1 minute

3. Thresholds:
   http_req_duration{group:"home"} p(95) < 800
   http_req_duration{group:"checkout"} p(95) < 1500
   http_req_failed: rate<0.01
   checks: rate>0.99

4. Use scenarios for read mix vs. write mix to keep RPS-per-endpoint realistic.

5. /loadtest/k6/run.sh:
   #!/usr/bin/env bash
   set -euo pipefail
   k6 run --vus-max 300 --out json=results.json /loadtest/k6/scenarios.js

6. Reporting:
   - After run, the script summarizes pass/fail thresholds and uploads results.json to Backblaze B2 under loadtests/<date>/.

7. Run on staging first, never directly on production. The first production load test is a Sunday 03:00 maintenance window with explicit human approval.

DO NOT load-test fin-svc /v1/wallet/withdraw at high QPS without disabling the SMS provider integration to avoid charging real money.
DO NOT skip the warm-up stage; cold caches will skew p95.
```

**Verification / Done Criteria:**
- [ ] k6 run with 300 VUs sustained passes thresholds on staging.
- [ ] DB QPS < 200 with cache enabled (verified via Postgres pg_stat_statements).
- [ ] Outbox publish lag stays < 1 s p95.
- [ ] No unhandled errors in fin-svc or core-svc logs.

---

## Prompt 6.2 — Final Launch Checklist Automation

**Phase & Goal:** Phase 6. Encode the launch readiness criteria as a single script that returns 0 only when ALL items pass; block deploys until then.

**Copy-Paste Prompt for Claude Code:**

```
READ FIRST: CLAUDE.md, DISASTER_RECOVERY.md, LEDGER_GUIDE.md, INFRASTRUCTURE.md.

Create /scripts/launch-readiness.sh that exits 0 iff every check passes; print a colored matrix showing which checks failed.

CHECKS:

1. All container hardening flags applied (parse `docker inspect` for security_opt, cap_drop, read_only).
2. mem_limit set on every service; sum within 24 GB minus 8 GB headroom.
3. postgres-ledger reachable ONLY from mopro-fin-net (run nc from core-svc and confirm failure).
4. Last 7 daily backups present in B2 (restic snapshots --tag full --json | jq … >= 7).
5. Last weekly restore drill result file shows OK.
6. unattended-upgrades enabled (systemctl is-enabled apt-daily-upgrade.timer).
7. UFW rules: only 80, 443, <ssh_high_port> open.
8. SSH password authentication disabled (grep PasswordAuthentication /etc/ssh/sshd_config).
9. CloudFlare proxy ON for api/seller/img.moproshop.com (curl with --resolve and check headers).
10. Caddy validate clean.
11. PgBouncer reachable from svc; pool sizes match config.
12. Redis maxmemory-policy = allkeys-lru.
13. Meilisearch master key set; no public access.
14. Wallet trigger present (SELECT trigger_name FROM information_schema.triggers WHERE trigger_name='ledger_balance_check').
15. wallet_schema.outbox count of unpublished < 100.
16. Hourly reconcile cron present and last run delta = 0.
17. Healthchecks.io: backup + restore + reconcile + disk-hygiene UUIDs all green.
18. golangci-lint clean on tip of main.
19. `go test -race ./...` passes on tip of main.
20. property_test.go ledger invariant passes.
21. mopro CLI available on PATH on the VDS.
22. Sentry DSN configured for core-svc, fin-svc, jobs-svc.
23. Grafana dashboards imported: HTTP RED, Outbox lag, Ledger balance time series, DLQ size.

Each check is implemented as a function returning 0/1 and a human-readable message. The script aggregates and prints a summary like:

  [ OK ] hardening_flags
  [ OK ] mem_limits
  [FAIL] cloudflare_proxy_seller   reason: orange cloud OFF
  [ OK ] caddy_validate
  ...
  Result: 22/23 passed. NOT READY.

Exit 0 only when all 23 pass.

GitHub Actions adds a job that runs this script against staging before tagging a production deploy. The job fails the deploy on red.

DO NOT skip a check. If a check is hard to automate, write a manual-attestation file `attest/launch.yaml` with a SIGNED entry and a 30-day expiry; the script reads it.
DO NOT mark the system production-ready while any check is red.
```

**Verification / Done Criteria:**
- [ ] Script returns non-zero on first run (expected).
- [ ] Each fix moves a row from FAIL to OK.
- [ ] Eventually exits 0 with all 23 checks green.
- [ ] CI job fails the deploy if the script is red.

---

## Closing Notes

- Every prompt above is a contract: copy it verbatim, do not soften the constraints.
- If Claude Code refuses or drifts, paste the relevant directive file (`CLAUDE.md`, `LEDGER_GUIDE.md`, …) into the conversation and re-run.
- Tasks span hours not minutes; verify each Done Criteria before continuing to the next prompt.
- When a task completes, run `make verify` and `./scripts/launch-readiness.sh` (Phase 6 onward) and only then move on.

> The path from empty repo to launch is roughly 26 prompts in this file. Worked end-to-end, the system reaches a state where 30K users/hour land safely on a single VDS, with double-entry ledger guarantees, automatic disaster mitigations, and full observability. There is no shortcut.

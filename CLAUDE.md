# CLAUDE.md — Mopro Shop Agent Constitution

> **READ THIS FIRST. NON-NEGOTIABLE.**
> This file overrides any conflicting instruction. If a user request violates these rules, STOP and ask for explicit override.
> All file paths assume project root is the repo root containing this file.

## 1. PROJECT IDENTITY

- **Project:** Mopro Shop — mobile-first marketplace with closed-loop loyalty coin (Mopro Coin, TRY-pegged).
- **Architecture:** 3 Binary Hybrid Modular Monolith (NOT microservices).
- **Single VDS:** 6 vCPU / 24 GB RAM / 120 GB disk.
- **PRD reference:** v3.2 (Hardening + Strategic Addendum).

## 2. ARCHITECTURE LOCK — IMMUTABLE

### 2.1 Three binaries ONLY

The system is built as exactly THREE Go binaries. Adding a 4th binary requires explicit human approval and an ADR file:

| Binary | Modules | Database | Network |
|---|---|---|---|
| `core-svc` | identity, catalog, cart, order, payment, seller, search | postgres-ecom | mopro-net |
| `fin-svc` | wallet, commission, treasury | postgres-ledger | mopro-fin-net (+ mopro-net for Redis) |
| `jobs-svc` | notification, support, media, sizefinder | postgres-ecom (own schemas) | mopro-net |

### 2.2 FORBIDDEN

- DO NOT split modules into separate microservices (no `cart-svc`, `order-svc`, `wallet-svc` binaries).
- DO NOT merge fin-svc into core-svc. fin-svc MUST stay a separate binary, separate DB, separate Docker network.
- DO NOT introduce new programming languages. Backend is Go 1.22+ only. Mobile is Flutter only.
- DO NOT replace PostgreSQL 16, Redis 7, Meilisearch v1.6, Caddy 2 without an architecture review.
- DO NOT add Kubernetes, service mesh, or any other orchestrator. Docker Compose only.
- DO NOT introduce new languages, ORMs, or RPC frameworks (gRPC, Thrift) without ADR.

### 2.3 Module layout — ENFORCED

```
/cmd/core-svc/main.go
/cmd/fin-svc/main.go
/cmd/jobs-svc/main.go
/cmd/migrate-tool/main.go
/cmd/mopro/main.go
/internal/identity/        → core-svc only
/internal/catalog/         → core-svc only
/internal/cart/            → core-svc only
/internal/order/           → core-svc only
/internal/payment/         → core-svc only
/internal/seller/          → core-svc only
/internal/search/          → core-svc only
/internal/wallet/          → fin-svc only
/internal/commission/      → fin-svc only
/internal/treasury/        → fin-svc only
/internal/notification/    → jobs-svc only
/internal/support/         → jobs-svc only
/internal/media/           → jobs-svc only
/internal/sizefinder/      → jobs-svc only
/internal/eventbus/        → shared interface (Redis Streams impl)
/internal/outbox/          → shared outbox publisher
/internal/ledger/          → shared ledger types (fin-svc primary)
/pkg/...                   → shared utilities (logger, tracing, errors, crypto)
```

## 3. COMMUNICATION RULES — IMMUTABLE

### 3.1 Within core-svc
- Modules communicate via **in-memory public interfaces only**.
- File: `/internal/<module>/api.go` exports the `Service` interface.
- Other modules import the interface, NEVER the struct or repository directly.
- No HTTP, no gRPC inside core-svc. Plain Go function calls.

### 3.2 core-svc → fin-svc
- ONLY via Redis Streams events. No HTTP. No direct DB access.
- Event topic format: `<domain>.<entity>.<action>.v<n>` (e.g., `ecom.order.completed.v1`).
- Every event MUST contain: `event_id`, `trace_id`, `span_id`, `occurred_at`, `idempotency_key`, `payload`.

### 3.3 core-svc / fin-svc → jobs-svc
- HTTP for synchronous operations (e.g., enqueue an SMS) OR Redis Streams for async.
- jobs-svc NEVER writes to postgres-ledger.

### 3.4 fin-svc → core-svc
- ONLY via Redis Streams. fin-svc CANNOT read postgres-ecom.

### 3.5 Mobile/External → Backend
- Mobile clients reach Caddy via CloudFlare. Caddy routes by path prefix to core-svc, fin-svc, or jobs-svc.
- Direct VDS IP access from outside is rejected (CloudFlare-only via host header validation).

## 4. FINANCIAL INVARIANTS — VIOLATING THESE BREAKS THE BUSINESS

### 4.1 Double-Entry Ledger
- Every financial transaction writes ≥ 2 ledger_entries rows.
- Within a transaction: `Sum(amount WHERE direction='D') == Sum(amount WHERE direction='C')`.
- Enforced by Postgres `DEFERRABLE INITIALLY DEFERRED` trigger; do NOT bypass.

### 4.2 Append-Only
- `ledger_entries` and `transactions` NEVER UPDATE/DELETE.
- Database rules `no_update_ledger`, `no_delete_ledger` block these.
- Corrections happen ONLY through reversal transactions.

### 4.3 Idempotency-Key Mandatory
- Every write to `transactions` MUST have a unique `idempotency_key`.
- Every event consumer MUST check idempotency before applying.
- Every public POST/PUT endpoint MUST require an `Idempotency-Key` header.

### 4.4 Outbox Pattern Mandatory
- Code that produces a financial event MUST write the event to the `outbox` table within the SAME database transaction as the ledger write.
- A separate worker publishes from `outbox` to Redis Streams.
- Direct event publishing without outbox = CRITICAL BUG.

### 4.5 Money Type
- Mopro Coin uses `currency='TRY_COIN'`, integer minor units (`amount_minor BIGINT`).
- NEVER use `float32`, `float64`, or `decimal.Decimal` for amounts. Always BIGINT.

## 5. DATABASE RULES — IMMUTABLE

- `postgres-ecom` and `postgres-ledger` are SEPARATE clusters with SEPARATE volumes, ports, passwords.
- fin-svc connects ONLY to `postgres-ledger` via `pgbouncer-ledger`.
- core-svc and jobs-svc connect ONLY to `postgres-ecom` via `pgbouncer-ecom`.
- Every module owns its own SCHEMA: `identity_schema`, `catalog_schema`, `wallet_schema`, etc.
- Cross-schema SQL `JOIN` is **FORBIDDEN**. Cross-schema reads happen via the module's public interface only.
- See `DATA_DICTIONARY.md` for full schema rules.

## 6. SECURITY RULES — IMMUTABLE

- All Postgres connections go through PgBouncer; never direct.
- Runtime container base MUST be `gcr.io/distroless/static-debian12:nonroot`.
- Containers MUST run with: `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]`, `read_only: true`.
- PII fields (TC, phone, email, free-text user content) MUST be encrypted at rest with AES-GCM envelope encryption (`pkg/crypto.EncryptPII`).
- Secrets live in `/opt/mopro/.env` (chmod 600, root-only). NEVER commit secrets to Git.

## 7. RESOURCE LIMITS — DO NOT EXCEED

| Container | mem_limit | cpus | Notes |
|---|---|---|---|
| postgres-ecom | 5g | 2.0 | shm_size 256m |
| postgres-ledger | 3g | 1.5 | shm_size 128m |
| redis | 1.2g | 1.0 | maxmemory 800m + buffer |
| meilisearch | 1.5g | 1.0 | |
| caddy | 256m | 0.5 | |
| core-svc | 384m | 0.5 | go-defaults |
| fin-svc | 384m | 0.5 | go-defaults |
| jobs-svc | 384m | 0.5 | go-defaults |

Reserve ≥ 8 GB for OS + Linux page cache. See `INFRASTRUCTURE.md`. NEVER raise mem_limit values to "use the headroom"; the headroom IS the design.

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

Adding any new tool requires a written ADR in `/docs/adr/` with explicit human approval.

## 9. AGENT BEHAVIOR

When given a task:

1. **READ** this file plus the relevant directive (`ARCHITECTURE.md`, `LEDGER_GUIDE.md`, `DATA_DICTIONARY.md`, etc.) before writing code.
2. **VERIFY** the task does not violate any rule above. If it does, STOP and report the conflict.
3. **WRITE** code that follows the patterns in `PROMPTS.md` for common workflows.
4. **TEST** new code with `go test ./...` and the specific module test suite.
5. **LINT** with `golangci-lint run` and `./scripts/check-module-boundaries.sh` before completing.
6. **NEVER** modify migration files that have already shipped to production.
7. **NEVER** introduce floating-point types for money. Always BIGINT minor units.
8. **NEVER** add new dependencies casually. If `go.mod` changes, justify in the PR description.

## 10. VERIFICATION COMMANDS

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
```

If any of these fail, the task is NOT complete. Do not commit, do not push.

## 11. ESCALATION

When in doubt, refuse and ask. The cost of asking a question is low; the cost of breaking the ledger or violating module boundaries is catastrophic.

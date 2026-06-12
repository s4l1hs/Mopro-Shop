# Mopro Shop

Mobile-first Turkish marketplace with a perpetual cashback model.  
Architecture: 3-binary Hybrid Modular Monolith · Go 1.25 · PostgreSQL 16 · Redis 7

---

## Quick Start (local)

```bash
# Create your local .env (see DEVELOPMENT.md § 3 for the required variables)
: > .env && chmod 600 .env
# fill in .env with dev values
./scripts/install-hooks.sh
go mod download
make verify
make run-local
curl -sf http://localhost/healthz
```

## Binaries

| Binary | Modules | DB |
|---|---|---|
| `core-svc` | identity, catalog, cart, order, payment, seller, search | postgres-ecom |
| `fin-svc` | wallet, commission, treasury, cashback-engine, seller-payout-engine | postgres-ledger |
| `jobs-svc` | notification, support, media, sizefinder | postgres-ecom |

All three binaries are built from a single Go module (`github.com/mopro/platform`).
`core-svc` ↔ `fin-svc` communicate exclusively via Redis Streams — no direct HTTP or DB
cross-access.

## Key Invariants (read CLAUDE.md before touching anything)

- All amounts in integer minor units (`BIGINT`). **No floats for money.**
- Every financial write uses the outbox pattern. `XADD` directly is a critical bug.
- `core-svc` ↔ `fin-svc`: Redis Streams only. No HTTP calls between them.
- Double-entry ledger enforced by a `DEFERRABLE` Postgres constraint trigger.
- Cashback v6 PERPETUAL: `monthly_coin = (commission × 5000 bps) / 10000 / 12`, forever.
- Seller payout: `unlock_at = delivered_at + 3 business days` (TR calendar).
- Idempotency: every POST/PUT endpoint requires `Idempotency-Key`; duplicate keys replay
  the cached response byte-for-byte from the Redis dedup store (24 h TTL).

## Verification

```bash
make verify          # fmt + vet + test + lint + boundary checks + property tests
make build-core      # go build ./cmd/core-svc
make build-fin       # go build ./cmd/fin-svc
make build-jobs      # go build ./cmd/jobs-svc
```

## Launch Readiness

Before deploying to production, run the automated checklist (requires VDS SSH access):

```bash
./deploy/scripts/launch-readiness.sh           # full check — 36+ assertions
./deploy/scripts/launch-readiness.sh --section A  # infrastructure only
./deploy/scripts/launch-readiness.sh --json       # machine-readable output
```

The checklist covers: infrastructure, security, financial invariants, observability,
performance SLOs, data seeding, backups, and operational readiness.
Expected result: all green + documented WARNs (see `docs/runbooks/launch-day.md`).

## Project Documents

| File | Purpose |
|---|---|
| `CLAUDE.md` | Constitution — agent rules, architecture locks, financial invariants |
| `ARCHITECTURE.md` | System topology and module communication patterns |
| `DATA_DICTIONARY.md` | Full database schema reference |
| `LEDGER_GUIDE.md` | Double-entry accounting rules and account structure |
| `INFRASTRUCTURE.md` | Resource limits, container config, VDS specs |
| `DISASTER_RECOVERY.md` | Backup, restore, and incident runbooks |
| `DEVELOPMENT.md` | Local setup, environment variables, test commands |
| `SECURITY.md` | Key rotation, PII handling, OTP security |
| `PROMPTS.md` | Phase-by-phase implementation guide |
| `docs/` | Architecture decision records, runbooks, audit logs |

## Contributing

See `CONTRIBUTING.md` for the development workflow, code conventions, and PR process.

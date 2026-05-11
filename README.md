# Mopro Shop

Mobile-first Turkish marketplace with a perpetual cashback model.  
Architecture: 3-binary Hybrid Modular Monolith · Go 1.22+ · PostgreSQL 16 · Redis 7

## Quick Start (local)

```bash
cp .env.example .env.local
chmod 600 .env.local
# fill in .env.local with dev values
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

## Key Rules (read CLAUDE.md before touching anything)

- All amounts in integer minor units (BIGINT). **No floats for money.**
- core-svc ↔ fin-svc: Redis Streams only. No HTTP between them.
- Every financial event uses the outbox pattern. Never XADD directly.
- Cashback v6 PERPETUAL: `monthly_coin = (commission × 5000bps) / 10000 / 12`, forever.
- Seller payout: `unlock_at = delivered_at + 3 business days` (TR calendar).

## Verification

```bash
make verify          # fmt + vet + test + lint + boundaries + property tests
make build-core      # go build ./cmd/core-svc
make build-fin       # go build ./cmd/fin-svc
make build-jobs      # go build ./cmd/jobs-svc
```

## Spec Files

| File | Purpose |
|---|---|
| `CLAUDE.md` | Constitution — read this first |
| `ARCHITECTURE.md` | System topology |
| `DATA_DICTIONARY.md` | Database schemas |
| `LEDGER_GUIDE.md` | Financial accounting rules |
| `INFRASTRUCTURE.md` | Resource limits |
| `DISASTER_RECOVERY.md` | Operational runbooks |
| `DEVELOPMENT.md` | Local setup & testing |
| `PROMPTS.md` | Phase-by-phase build guide |

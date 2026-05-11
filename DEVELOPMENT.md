# DEVELOPMENT.md — Local Setup, Testing, and Pre-Push Checks

## 1. Prerequisites

| Tool | Version | Install |
|---|---|---|
| Go | 1.22+ | https://go.dev/dl/ |
| Docker Engine | 24+ | https://docs.docker.com/engine/install/ |
| Docker Compose | v2 plugin | bundled with modern Docker |
| golangci-lint | 1.55+ | `brew install golangci-lint` or curl install |
| restic | 0.16+ | for testing backup paths locally |
| direnv | optional | manage `.env.local` ergonomically |
| Node.js | 20+ | for any front-end tooling |
| Flutter | 3.x | mobile development |

## 2. First-Time Setup

```bash
git clone git@github.com:mopro/platform.git
cd platform

# 1) Copy env template, fill in safe local values
cp .env.example .env.local
chmod 600 .env.local

# 2) Pre-commit hooks
./scripts/install-hooks.sh

# 3) Initialize tools
go mod download
golangci-lint --version
```

## 3. .env.local — Required Variables

`.env.local` holds dev-only secrets. NEVER commit it. NEVER copy production values into it.

```bash
# DB passwords — local only
ECOM_DB_PASSWORD=dev_ecom_pw
LEDGER_DB_PASSWORD=dev_ledger_pw
IDENTITY_DB_PASSWORD=dev_identity_pw
WALLET_DB_PASSWORD=dev_wallet_pw

# Redis
REDIS_PASSWORD=dev_redis_pw

# Meilisearch
MEILI_MASTER_KEY=dev_meili_master_key

# Caddy email (Let's Encrypt local: use staging endpoint or skip)
CADDY_EMAIL=dev@localhost

# JWT signing key (32 bytes base64 for HS256)
JWT_SIGNING_KEY=dGhpc2lzYWRldnNpZ25pbmdrZXktMzJieXRlcw==

# PII encryption key (256-bit base64)
PII_KEK_BASE64=YjY0LWVuY29kZWQta2VrLTMyYnl0ZXMtZm9yLWFlcy1nY20=

# PSP (use sandbox creds in dev)
PSP_API_KEY=sandbox_xxx

# Backblaze B2 (optional in dev; use minio for fully offline dev)
B2_KEY_ID=
B2_APP_KEY=

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

# Slack/PagerDuty (optional in dev — leave blank to disable alerts)
SLACK_WEBHOOK=
SLACK_PANIC_WEBHOOK=
PAGERDUTY_API=
BETTERSTACK_INCIDENT_API=
```

## 4. Bring Up the Local Stack

```bash
# Full stack
docker compose --env-file .env.local up -d

# Watch logs (one binary at a time)
docker compose --env-file .env.local logs -f core-svc
docker compose --env-file .env.local logs -f fin-svc
docker compose --env-file .env.local logs -f jobs-svc

# Smoke check
curl -sf http://localhost/healthz
curl -sf http://localhost:9090/metrics

# Tear down (preserves volumes)
docker compose down

# Tear down + wipe data (use carefully)
docker compose down -v
```

## 5. Iterating on a Single Binary

```bash
# Stop the in-container instance
docker compose stop core-svc

# Run from source against the running stack (DB on localhost via port-forward)
export $(grep -v '^#' .env.local | xargs)
go run ./cmd/core-svc
```

If port-forward is not configured, run inside the network:

```bash
docker compose run --rm -e DB_HOST=postgres-ecom -e DB_PORT=5432 \
    --service-ports core-svc go run ./cmd/core-svc
```

## 6. Database Tools

```bash
# psql into ecom
docker exec -it postgres-ecom psql -U ecom_admin -d mopro_ecom

# psql into ledger
docker exec -it postgres-ledger psql -U ledger_admin -d mopro_ledger

# Run pending migrations (golang-migrate)
go run ./cmd/migrate-tool ecom up
go run ./cmd/migrate-tool ledger up

# Reset a local DB (DEV ONLY — wipes data)
docker compose down
sudo rm -rf data/postgres-ecom data/postgres-ledger
docker compose up -d postgres-ecom postgres-ledger
```

## 7. Testing Standards

### 7.1 Unit tests

```bash
go test ./...
go test -race ./...
go test -cover ./...
```

Coverage minimum: 70% per module. fin-svc modules: 85%.

### 7.2 Property-based testing — MANDATORY for ledger

Any change to `wallet`, `commission`, or `treasury` MUST add or extend property tests with `gopter`.

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
    Type    string
    Account int64
    Amount  int64
}

func genOp() gopter.Gen {
    return gen.Struct(reflect.TypeOf(Op{}), map[string]gopter.Gen{
        "Type":    gen.OneConstOf("commission", "withdraw", "reversal"),
        "Account": gen.Int64Range(1, 100),
        "Amount":  gen.Int64Range(1, 100_000_00),
    })
}

func TestProperty_LedgerStaysBalanced(t *testing.T) {
    params := gopter.DefaultTestParameters()
    params.MinSuccessfulTests = 1000
    properties := gopter.NewProperties(params)

    properties.Property("Sum(D) - Sum(C) is always 0", prop.ForAll(
        func(ops []Op) bool {
            db := setupTestLedger(t)
            for _, op := range ops { applyOp(t, db, op) }
            return totalDelta(db) == 0
        },
        gen.SliceOf(genOp()),
    ))
    properties.TestingRun(t)
}
```

CI fails if property tests fail. No exceptions.

### 7.3 Integration tests

```bash
go test -tags=integration ./...
```

Integration tests spin up a fresh Postgres + Redis via testcontainers-go. They MUST be hermetic (no shared state across runs).

## 8. Pre-Push Verification

Run before every `git push`:

```bash
make verify
```

`Makefile`:

```makefile
.PHONY: verify fmt vet test lint boundaries

verify: fmt vet test lint boundaries

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
```

Pre-push hook installed by `scripts/install-hooks.sh` runs `make verify` automatically.

## 9. Module Boundary Linter

`.golangci.yml` (excerpt):

```yaml
linters:
  enable:
    - depguard
    - gocyclo
    - errcheck
    - revive
    - gosec
    - gocritic

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
      fin-no-ecom:
        files:
          - "internal/wallet/**"
          - "internal/commission/**"
          - "internal/treasury/**"
        deny:
          - pkg: github.com/mopro/platform/internal/order
            desc: "fin-svc MUST NOT import core-svc internals"
          - pkg: github.com/mopro/platform/internal/payment
            desc: "fin-svc MUST NOT import core-svc internals"
      modules-only-via-api:
        files:
          - "internal/order/**"
        deny:
          - pkg: github.com/mopro/platform/internal/catalog/repository
            desc: "Use internal/catalog public interface, not internal types"
          - pkg: github.com/mopro/platform/internal/catalog/service
            desc: "Use internal/catalog public interface, not internal types"
```

## 10. `scripts/check-module-boundaries.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Block raw cross-schema SQL in /migrations and /internal/**/sql files
SCHEMAS="identity|catalog|cart|order|payment|seller|search|wallet|commission|treasury|notification|support|media|sizefinder"
if grep -rE "FROM\s+($SCHEMAS)_schema\." \
    --include='*.sql' --include='*.go' \
    internal/ migrations/ \
    | grep -vE '/(identity|catalog|cart|order|payment|seller|search|wallet|commission|treasury|notification|support|media|sizefinder)/' ; then
    echo "ERROR: cross-schema reference detected"
    exit 1
fi

# Block float for money types
if grep -rE '(float32|float64).*amount' --include='*.go' internal/ ; then
    echo "ERROR: float type used for amount; use BIGINT minor units"
    exit 1
fi

# Block direct redis.XAdd outside outbox publisher
if grep -rE 'redis.*XAdd' --include='*.go' internal/ \
    | grep -v internal/eventbus/redis_bus.go \
    | grep -v internal/outbox/publisher.go ; then
    echo "ERROR: redis.XAdd outside outbox publisher; route through outbox"
    exit 1
fi

echo "boundaries OK"
```

## 11. CI/CD Local Mirror

```bash
# Same checks GitHub Actions runs:
make verify

# Optional: run with the same Trivy scan locally
docker buildx build -t local/core-svc -f build/Dockerfile --build-arg SERVICE=core-svc .
trivy image --severity HIGH,CRITICAL local/core-svc
```

## 12. Common Tasks Cheat Sheet

```bash
# Add a Go module skeleton
./scripts/new-module.sh internal/<name>

# Generate event payload types from schema
go generate ./internal/eventbus/...

# Tail logs and grep for trace_id
docker compose logs -f --no-color | grep '"trace_id":"abc123"'

# Inspect Redis Streams
docker exec redis redis-cli -a "$REDIS_PASSWORD" XINFO STREAM ecom.order.completed.v1

# Check pending outbox
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
  "SELECT count(*) FROM order_schema.outbox WHERE published_at IS NULL"
```

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

## 14. Code Style

- `gofmt`-clean. No exceptions.
- Errors are values; wrap with `fmt.Errorf("...: %w", err)`.
- No `panic` except for genuinely unrecoverable startup faults.
- Context as first argument for any IO-bound function.
- Tests live next to source as `<thing>_test.go`.
- Public APIs documented with godoc comments starting with the symbol name.

## 15. When in Doubt

Read in this order:
1. `CLAUDE.md` — non-negotiable rules
2. `ARCHITECTURE.md` — topology
3. `DATA_DICTIONARY.md` — DB rules
4. `LEDGER_GUIDE.md` — financial rules (if touching fin-svc or any ledger code)
5. `INFRASTRUCTURE.md` — resource limits
6. `DISASTER_RECOVERY.md` — operational runbooks
7. `PROMPTS.md` — workflow templates
8. This file — local dev

If still unclear: STOP and ask the human owner.

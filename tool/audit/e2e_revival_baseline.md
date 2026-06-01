# E2e Revival Baseline — `chore/revive-internal-e2e-suite`

Audit of the rotted `internal/e2e/` integration suite. Generated 2026-06-01.
Base: `main@449bf1f8` (post stack-drain; PRs #34/#36/#37 + #38 on main).

## Reproduction — the prompt's §1.1 command is itself wrong

`go build -tags=integration ./internal/e2e/...` → **exit 0** (misleadingly green).
`go build` does **not** compile `_test.go` files, so it can never catch test rot.
The real reproduction is test-compilation:

```sh
go test -tags=integration -gcflags=-e -run xxxNoMatch ./internal/e2e/...   # -gcflags=-e: no truncation
# or: go vet -tags=integration ./internal/e2e/...
```

→ **17 compile errors across 4 files** (`dlq_e2e_test.go` compiles clean). This is the
exact §6.2 lesson: test files are invisible to `go build` without the right tags. The §5
gate must use `go test`, not `go build`.

## §2.1 Breakage inventory + §2.2 migration paths

5 distinct breakage classes (< the §1.6 ~10-class threshold → **ships as one PR**, no 4a/4b split).

| # | Class | Symbol / change | Sites | Migration path |
|---|-------|-----------------|-------|----------------|
| **A** | Signature change | `cashback.NewService` — param 5 `wallet.Service`→`cashback.WalletPoster`; **new** param 7 `*metrics.BusinessMetrics` | `delivered:195`, `kargo:363`, `redis:75`, `order:102` (4) | Append a 7th arg. `delivered` passes a real `wallet.Service` (satisfies `WalletPoster`) → append `nil` for biz. The `nil,nil` sites (kargo/redis/order, plan-creation-only) stay nil walletPoster, append `nil` biz. Nil-safe: `NewService` nil-guards `log`; `BusinessMetrics` methods are nil-safe (`TestBusinessMetrics_NilSafe`). |
| **B** | Interface growth | `cart.Service.SeedStockIfAbsent(ctx, variantID int64, stock int) error` | mocks `cartMock` (`order:372`), `multiItemCartMock` (`delivered:70`) | Add stub method returning `nil` to both mocks. |
| **C** | Interface growth | `catalog.Service.HomeBanners(ctx) ([]HomeBannerRow, error)` | mocks `catalogMock` (`order:345`), `multiVariantCatalogMock` (`delivered:34`) | Add stub returning `nil, nil` to both mocks. |
| **D** | Removed entry point | `cashback.Service.RunMonth(ctx, period, now, currency)` removed | `delivered:408`, `delivered:431` (2) | → `PayMonthlyInstallments(ctx, runDate)`. Period is now derived internally from `runDate`; currency is fixed at `NewService` time (`cashbackCurrency`). Return type `PaymentSummary` keeps `.Processed/.Skipped/.Failed` → assertions unchanged. |
| **E** | Removed entry point | `cashback.Service.CreatePlanForOrder(ctx, ev) error` removed | `kargo:385`, `order:244`, `order:249` (3) | → `CreatePlanFromDelivery(ctx, ev) (Plan, error)`. Discard the `Plan` return. **Must also populate `ev.PriceMinor` + `ev.CommissionBps`** — v8 reads these "direct fields"; events here only set `Items`, so a pure rename hits the `PriceMinor <= 0` guard and silently skips plan creation. Mirror production `consumer.go`: `priceMinor = Σ items.UnitPriceMinor*Qty`, `commissionBps = items[0].CommissionPctBps`. |

### Authoritative migration reference: `internal/cashback/consumer.go`
The production consumer resolves the v8 fields from the wire event, falling back to summing
items for pre-v8 payloads (lines ~71–82). The Class E test migration mirrors this exactly.

## §2.3 Scenario inventory

| Test | File | Scenario | Still meaningful (v8)? | Dup coverage? |
|------|------|----------|------------------------|---------------|
| `TestE2E_OrderToCashbackAndPayout` | order_to_cashback | checkout → deliver → cashback plan (direct create) → seller payout | Yes | Cashback math unit-tested (property-cashback); e2e tests the full wiring — not duplicative |
| `TestE2E_FullCheckoutToPayoutViaRedis` | order_to_cashback_redis | full flow via Redis event → consumer creates plan | Yes | No |
| `TestE2E_KargoWebhookToCashbackPlan` | kargo_to_cashback | shipping webhook → delivered → cashback plan | Yes | No |
| `TestE2E_DeliveredEventTwoSellersIdempotent` | delivered_multi_seller | multi-seller delivered idempotency + monthly cron (RunMonth) | Yes | No |
| `TestE2E_PoisonMessageFullCycle` | dlq_e2e | DLQ poison-message cycle | Yes (compiles clean) | No |
| `TestE2E_ReplayReloops` | dlq_e2e | DLQ replay re-loop | Yes (compiles clean) | No |
| `TestProperty_DLQContainsExactlyPermanentFailures` | dlq_e2e | DLQ invariant | Yes (compiles clean) | No |

**No scenario is rendered meaningless by v8** → no `REVIVAL_GAP:` markers expected. No silent
deletions. All scenarios migrate mechanically.

## §2.4 CI gate context

- `make verify` today runs: `fmt vet test lint boundaries property-cashback property-payout
  property-ledger property-timex property-order verify-image-manifest verify-contrast`.
- The `test` target is `go test ./...` **without** `-tags=integration` → `internal/e2e/` (all
  files `//go:build integration`) is **excluded**. This is the root cause of the silent rot.
- **Bootstrap precedent:** property tests depend on `pg-ledger-test-up` — an *idempotent*
  target that reuses a running `pg-ledger-test:6434` container or starts one. `make verify`
  already requires docker. Convention = self-bootstrap via an idempotent `-up` target, container
  left running for dev iteration (NOT torn down).
- **e2e infra needs:** redis (`REDIS_E2E_ADDR`, default `localhost:6381`), pg-ecom
  (`ORDER_E2E_DSN`, `:6435`), pg-ledger (`LEDGER_E2E_DSN`, `:6436`). The suite's `TestMain`
  applies its own schema via `setupEcomSchema`/`setupLedgerSchema` → bootstrap only needs
  **empty** postgres + redis (no migration files to apply, unlike pg-ledger-test-up).
- **Hard-fail vs skip:** `TestMain` does `os.Exit(1)` when postgres is unreachable (does not
  skip); individual tests `t.Skipf` only on redis. Gate plan: add an idempotent `e2e-test-up`
  target (mirrors `pg-ledger-test-up`) + an `integration-e2e` target wired into `verify`, so the
  containers are present whenever `verify` runs → no hard-fail. Consistent with the existing
  docker requirement.
- An existing `make test-e2e` target spins fresh containers and tears them down; the gate will
  instead reuse idempotently (faster dev loop), keeping `test-e2e` as the throwaway-run variant.

## §5 gate plan

1. `e2e-test-up` (idempotent): start `redis-e2e:6381`, `pg-ecom-e2e:6435`, `pg-ledger-e2e:6436`
   if absent; reuse if present; wait for postgres readiness.
2. `integration-e2e: e2e-test-up` → `REDIS_E2E_ADDR=... ORDER_E2E_DSN=... LEDGER_E2E_DSN=...
   go test -tags=integration ./internal/e2e/... -count=1 -race -timeout 5m`.
3. Wire `integration-e2e` into the `verify` target list.
4. Smoke-test (§5.4): inject a bogus `cashback.X()` call → confirm `make verify` fails at the
   e2e gate → revert → confirm green.
5. CI runner (§5.3): check whether CI runs `make verify`; if not, the gate only fires locally →
   Backlog item.

## §1.6 triggers fired during audit

None. 5 breakage classes (< 10), all mechanically migratable, no scenario gaps. Default single-PR ships.

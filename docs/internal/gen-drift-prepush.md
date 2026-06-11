# Stabilize main: generated-files drift + pre-push root fix

Two problems landed together: `main`'s **"Generated files in sync"** required check
went red after #190, and the recurring `--no-verify` pushes that let it through.
This doc records what drifted and why the local gate had stopped running.

## 1. The generated-files drift

The **"Generated files in sync"** job (`.github/workflows/openapi-ci.yml`)
regenerates the Go types (oapi-codegen) **and** the Dart client (dart-dio, via the
`openapitools/openapi-generator-cli:v7.10.0` Docker image), then runs
`git diff --exit-code internal/api/gen/ mobile/packages/mopro_api/`.

### 1a. The drift that made it red — a non-deterministic FILES manifest line

Regenerating locally showed the **Go side was already in sync** (zero diff). The
red was entirely in the Dart client's generator manifest:

```
 mobile/packages/mopro_api/.openapi-generator/FILES
-test/delivery_address_test.dart
```

The dart-dio generator (this config) emits **zero** `test/*_test.dart` lines into
`FILES` — the manifest had **one** stray test-stub line. History explains it:
commit `1c6ca076 "chore(api): drop non-deterministic test-stub lines from dart
FILES manifest"` had already stripped these because they're non-deterministic;
#190 (`d89e8d29`) then re-added `test/delivery_address_test.dart`, reintroducing
exactly the non-determinism that was cleaned up. Regenerating drops it again, and
a second regen confirms it stays gone (deterministic in the "no test lines"
direction).

### 1b. The `Order` status enum was genuinely stale (fixed)

#190's contract test had to scope to the `DeliveryAddress` sub-object because the
live `Order` serialization diverged from the spec's `Order` schema. Confirmed
that the `Order.status` enum was **fictional**:

| | values |
|---|---|
| spec enum (before) | `pending, confirmed, preparing, shipped, delivered, cancelled, refunded` |
| `internal/order.OrderStatus` (truth) | `pending_payment, paid, shipped, delivered, cancelled, refunded, partially_refunded` |
| mobile `OrderStatus` (truth) | same 7 |

The spec listed three statuses the backend never emits (`pending, confirmed,
preparing`) and omitted three real ones (`pending_payment, paid,
partially_refunded`). Reconciled both occurrences (the `Order` schema + the
`GET /orders?status=` filter param) to the 7 real values, plus the stale
"pending/confirmed" wording on the cancel summary. The generated `OrderStatus`
constants are **not referenced outside `internal/api/gen/`**, so the regen is
build-safe (oapi-codegen re-disambiguates collision names like
`Paid`→`CashbackPaymentStatusPaid` — expected, no external refs).

### 1c. Discovery shift — full-Order conformance is still blocked (by a *different* drift)

Reconciling the enum did **not** fully unblock a whole-`Order` contract assertion.
The live envelope is `{"order": {...}, "items": [...], "actions": …, "refund": …}`
— `items` is a **sibling** of `order`, but the spec's `Order` schema **nests**
`items` inside the order. So validating the whole order object fails on
`property "items" is missing`. That items-placement divergence is a separate
response-shape/schema change (it would touch the mobile read-path) and is **out
of this gen-drift lane** — documented as a follow-up. The contract test now
asserts `status="paid"` is a member of the (now honest) `Order.status` enum
(`assertEnumMember`) + keeps the `DeliveryAddress` sub-object validation.

## 2. The pre-push hang (root of the `--no-verify` cascade)

`core.hooksPath = .githooks`. The **pre-push** hook ran the full `make verify`:

```
verify: fmt vet test lint boundaries migration-check lint-discipline
        property-cashback property-payout property-ledger
        integration-wallet … integration-* … verify-image-manifest verify-contrast
```

The `property-*` and `integration-*` suites need the Postgres + Redis test
**clusters up**; the cashback property/DB crons **never return** without them, so
the hook hangs. Devs reflexively `git push --no-verify` → the local gate stopped
running entirely → red required checks reached `main`.

### The fix — a fast, DB-free `verify-fast` for the *local* hook

New `make verify-fast` (and the pre-push hook now calls it) chains only the steps
that run **without any DB/Docker**:

```
verify-fast: fmt vet lint-discipline boundaries migration-check
             build-all test analyze i18n-check i18n-usage
```

- `fmt` (gofmt) · `vet` · `lint-discipline` (go/analysis) · `boundaries`
  (module-import rules) · `migration-check` (text DDL scan) — all fast, no DB.
- `build-all` — the three service binaries to `/tmp` (compile check).
- `test` — `go test -race ./...` (unit only; `//go:build integration` suites are
  excluded without `-tags=integration`, so no DB).
- `analyze` — new target: `cd mobile && flutter analyze --no-fatal-infos`
  (mirrors CI's green-on-compile gate).
- `i18n-check` (`--strict`, fails on extra keys) + `i18n-usage` (dead/missing
  ratchet).

`golangci-lint run` is intentionally **left to CI** (it has a known worktree
generated-file false-positive foot-gun and is slower); the full `verify` —
property/integration suites included — **stays the CI required gate** and is
unchanged. End-to-end local run: **~35s, exit 0, no hang.** A fast hook that
actually runs beats a heavy one that's always `--no-verify`'d.

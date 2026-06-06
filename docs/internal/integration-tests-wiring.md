# Wiring post-audit integration tests into `make verify`

> Closes the post-audit follow-up "wire analytics + delivery-ETA integration tests into make verify"
> (filed by #100 and #97). **Discovery also surfaced a broader gap** — many `//go:build integration`
> suites run in no CI gate at all — which is carved to a tracked follow-up (§4), not scope-crept here.

## 1. How integration tests reach CI today

`make verify` is the **only** path that runs `-tags=integration` tests in CI:
- `.github/workflows/make-verify.yml` → `make verify` (every PR + main push).
- `.github/workflows/nightly.yml` → `make soak` (wallet/payment/identity stress only).
- `.github/workflows/openapi-ci.yml` → `go test -race ./...` (**no** integration tag → build-tagged files excluded) + `-tags=contract`.
- `.github/workflows/e2e.yml` → Playwright (web/), unrelated to Go integration tests.

So "not in `make verify`" == "runs nowhere in CI."

### `verify` integration coverage (the chain)
`property-cashback/-payout/-ledger` (`-run Property`), `integration-wallet` (full wallet), `property-timex`,
`property-order` (**`-run Property`, no integration tag**), `integration-e2e/-cart/-identity/-identity-race/-payment`
(the **e2e-cluster** containers: `pg-ecom-e2e` :6435, `pg-ledger-e2e` :6436, `redis-e2e` :6381 — idempotent
reuse via `e2e-test-up`), `test-integration-catalog` (own ephemeral `pg-ecom-test` :6433).

## 2. Full `//go:build integration` inventory vs. coverage

| Package | Integration file(s) | Run by a `verify` target? |
|---|---|---|
| wallet, cashback, sellerpayout(Property), catalog, cart, identity, payment, e2e, order(Property), timex | — | ✅ yes |
| **analytics** | `integration_test.go` (Ingest, Consent, Identify, RecentlyViewed, Prune, Erase, **RefreshRecommendations**, **PopularPerCategory** #100) | ❌ **no target** — Gap 1 |
| **shipping** | *(none yet)* — `LookupTransit`/`LookupTransitDefault` only stub-tested | ❌ **no test exists** — Gap 2 |
| eventbus + outbox | autoclaim/dlq_integration/dlq_e2e + publisher | ⚠️ `test-integration-outbox` exists, **not in `verify`** |
| order (full) | `integration_test.go`, `returns_integration_test.go` | ⚠️ `test-integration-order` exists, **not in `verify`** |
| sellerpayout (full) | `sellerpayout_integration_test.go` | ⚠️ `test-integration-sellerpayout` exists, **not in `verify`** |
| api (fin) | `fin_integration_test.go` | ❌ no target |
| attachments, help, idempotency, inbox, reconcile, seller | `integration_test.go` (+ `reconcile_integration_test.go`) | ❌ no target |

## 3. The two named gaps (wired here)

### Gap 1 — analytics → `integration-analytics`
`internal/analytics/integration_test.go` reads `ANALYTICS_TEST_DSN` and its `TestMain` **self-bootstraps**
`analytics_schema` (CREATE SCHEMA + tables) on an **empty** postgres-ecom. So it reuses `e2e-test-up`'s
`pg-ecom-e2e` (:6435) with **zero new infra** — no migrations, no new container, exactly like `integration-identity`.
Known-green (validated on PG for #100). Wiring = one target + one slot on the `verify` line. Covers far more than
the per-category test (8 `TestIntegration_*` incl. recommendations + consent + erase).

### Gap 2 — delivery-ETA → new test + `integration-shipping`
`shipping.LookupTransit(ctx, market, origin, dest) (min, max int, found bool, err error)` joins
`ref_schema.shipping_zones` (origin→zone, dest→zone) × `ref_schema.transit_days`; `LookupTransitDefault(ctx, market)`
reads `ref_schema.transit_default`. All three tables + their TR seed live in **migration `0085_shipping_zones.up.sql`**
(self-contained `CREATE TABLE IF NOT EXISTS` + `INSERT … ON CONFLICT DO NOTHING`, assuming `ref_schema` exists).

New `internal/shipping/lookup_transit_integration_test.go` (reads `SHIPPING_TEST_DSN`, `t.Skip` when unset):
a per-test helper opens a **simple-protocol** pool (so a multi-statement file `Exec` runs every statement),
`CREATE SCHEMA IF NOT EXISTS ref_schema`, then execs the **real 0085 file** (`../../migrations/ecom/0085_shipping_zones.up.sql`)
— this reuses the seed verbatim **and validates it** (seed-correctness was the stated value in #97). No inline seed.

Expected values are **derived from the 0085 matrix** (`min = same?1:GREATEST(2,1+|Δtier|)`,
`max = same?2:min+1+(destTier3?1:0)`; tiers marmara/ege=1, ic_anadolu/akdeniz/karadeniz=2, dogu/guneydogu=3):

| origin → dest | zones (tiers) | min,max |
|---|---|---|
| istanbul → istanbul | marmara→marmara | 1,2 |
| erzurum → van | dogu→dogu | 1,2 |
| istanbul → izmir | marmara(1)→ege(1) | 2,3 |
| istanbul → ankara | (1)→ic_anadolu(2) | 2,3 |
| istanbul → diyarbakir | (1)→guneydogu(3) | **3,5** |
| diyarbakir → istanbul | (3)→(1) **west-bound** | **3,4** (asymmetric) |
| adana → trabzon | akdeniz(2)→karadeniz(2) | 2,3 |
| `LookupTransitDefault('TR')` | national fallback | 2,5 |

> Note: the prompt's sample asserted `istanbul→diyarbakir = 4,5`; the seed yields **3,5** (min uses
> `GREATEST(2, 1+2)=3`). Deriving from the file, not the sample, is the point of the test.

Plus `found=false` for unknown dest / unknown origin / unknown market, and a `LookupTransitDefault('XX')` miss.

Target reuses `e2e-test-up`'s `pg-ecom-e2e` (:6435), scoped **non-recursively** (`./internal/shipping/`) so the 6
carrier adapter sub-packages (aras/mng/…, already unit-tested by `go test ./...`) are not pulled in.

## 4. The broader gap (carved — TESTING_AUDIT follow-up, NOT this PR)

10 suites beyond the two named ones run in no CI gate. Wiring them is **not** a one-line change:

- **`test-integration-{order,sellerpayout,outbox}` exist but port-conflict with the e2e-cluster** — they bind
  `:6435` / `:6434` / `:6380`, the same ports `e2e-test-up` uses, so they can't simply be appended to `verify`.
  Reviving them means reworking each to **reuse** the e2e-cluster containers (the exact pattern of
  `chore/revive-cart-identity-integration-tests`, which was its own dedicated PR).
- **`api`(fin), `attachments`, `help`, `idempotency`, `inbox`, `reconcile`, `seller`** have no target — each needs
  per-package triage (which DB/schema, self-bootstrap vs migrations, green-or-rotted).

Wiring 10 never-CI'd suites risks turning `verify` red on rotted tests and violates this PR's anti-goal
("do not refactor existing integration tests"). Per §1.3/§5 of the prompt and the LOW-batch precedent (#87),
these are **carved to a tracked TESTING_AUDIT finding** with the per-package container map, to be revived in a
follow-up the way cart/identity were.

## 5. Acceptance
- `integration-analytics` + `integration-shipping` in the `verify` chain; both green under `make verify`.
- New shipping test: ≥5 representative `LookupTransit` pairs + default + unknown-origin/dest/market.
- Broader unwired set documented + carved (not silently dropped).
- The **filed** post-audit tail (analytics + delivery-ETA wiring) is at zero.

## 6. Commit plan
1. this doc.
2. wire analytics (`integration-analytics` target + `verify`).
3. new `lookup_transit_integration_test.go`.
4. wire shipping (`integration-shipping` target + `verify`).
5. docs closure — TESTING_AUDIT finding (carve) + parity-audit/ROADMAP/REPORT tail closure.

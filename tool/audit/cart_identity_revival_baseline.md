# Cart + Identity Integration-Test Revival — Baseline

Branch `chore/revive-cart-identity-integration-tests`. Base `main@9201cba4` (PR #41/#42/#43/#44/#47 merged).
Same pattern as PR #40's `internal/e2e/` revival; closes PR #42's "cart/identity integration-test rot" Backlog.

## Reproduction note
The prompt's `go build -tags=integration ./internal/{cart,identity}/...` returns **exit 0** —
`go build` does not compile `_test.go` files (the PR #40/#42 lesson). The real repro is
`go vet -tags=integration` / `go test -tags=integration -run xxx`:
- cart: **2** test-compile errors. identity: **5**.

## Breakage inventory + migration paths

### Cart — 1 class (interface growth)
`alwaysValidCatalog` (test stub of `catalog.Service`, defined in `integration_test.go:42`, used by
`integration_test.go:73` + `property_test.go:38` via `cart.NewService(repo, catalog.Service)`) implements
10 of `catalog.Service`'s 20 methods. **Missing 10** (compiler reports only `HomeBanners` first — PR #40
precedent: iterate): `HomeBanners, HomeFlashDeals, HomeMoodStories, HomeRails, ListAllVariantStocks,
ListProductsByIDs, ListReviews, ReviewProductID, ReviewsSummary, ToggleHelpfulVote`.
- **Migration:** add the 10 missing methods as `REVIVAL_MOCK` no-op stubs (same set + signatures used in
  PR #40's e2e catalog mocks).

### Identity — 1 class (signature change)
`identity.NewService` signature grew from 7→9 params:
`NewService(repo, sms.Provider, email.Provider, ratelimit.Limiter, jwt.Signer, market, locale, *slog.Logger, *metrics.BusinessMetrics)`.
The old test calls (7 args) are missing **`email.Provider`** (new param 3) and the appended
**`*slog.Logger`** + **`*metrics.BusinessMetrics`**. 5 call sites: `e2e_test.go:34`,
`integration_test.go:541/599/665`, `property_test.go:42`.
- **Migration:** add a `capturedEmail` test fake implementing `internal/identity/email.Provider`
  (`SendVerification(ctx, toEmail, code) error` + `SendPasswordReset(ctx, toEmail, resetToken) error`),
  mirroring the existing `capturedSMS`. At each call site: insert the email fake at position 3, append
  `slog.Default()` + `nil` (BusinessMetrics is nil-safe). No `email`-package import needed at the call
  site beyond the fake's definition.

## Scenario inventory (§2.3)
All scenarios are compile-broken only; none appear obsolete. Runtime check (§3.2) will confirm.
- **cart** (5+3): `TestIntegration_CartFlow/RemoveItem/Reserve_OutOfStock/Release_NotFound/CommitReservation`,
  `TestProperty_ConcurrentReservationAtomicity`, `TestStockReservation_ConcurrentGoroutines/NoOversell` —
  all current cart stock/reservation behavior; meaningful.
- **identity** (4 property + 5 e2e + 11 integ): OTP/JWT/refresh-rotation/mask-phone properties; full
  login/refresh-theft/step-up/logout/delete-me e2e; OTP+session+device+rate-limiter integration — all
  current identity behavior; meaningful.
No compile-level `REVIVAL_GAP:` expected. Schema drift (identity hand-rolls `identity_schema` in TestMain;
PR #40 precedent) checked at runtime in §3.2.

## CI gate plan (§2.4 / §4) — reuse PR #40's `e2e-test-up`
Neither suite needs new containers:
- **cart** → Redis only (`CART_TEST_REDIS`, `TestMain` FlushDB's a clean slate, hard-exits if absent).
- **identity** → postgres (`IDENTITY_TEST_DSN`; `TestMain` DROP+CREATEs `identity_schema`) + Redis
  (`IDENTITY_TEST_REDIS`, DB 1).
Both map onto `e2e-test-up`'s `redis-e2e:6381` + `pg-ecom-e2e:6435` (distinct schema/DB → no conflict;
sub-targets run sequentially in `make verify`). Plan:
```
integration-cart: e2e-test-up
	CART_TEST_REDIS=localhost:6381 go test -tags=integration ./internal/cart/... -count=1 -race -timeout 5m
integration-identity: e2e-test-up
	IDENTITY_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	IDENTITY_TEST_REDIS=localhost:6381 go test -tags=integration ./internal/identity/... -count=1 -race -timeout 5m
verify: … integration-cart integration-identity …
```
CI inherits automatically — `make-verify.yml` (PR #41) runs `make verify` end-to-end.

## §1.6 escape-hatch checks
- #2 (>12 classes): NO — 2 classes total. Ships as one PR.
- #1 (business-logic decision) / #3 (missing infra): none at compile time; re-evaluate after the §3.2 run.

# Audit — Cashback Constant Fix (`internal/e2e` build unblock)

Read-only baseline. Resolves the `cashback.ReferenceInterestRateBpsConst undefined`
compile error in the integration-tagged `internal/e2e/` suite, flagged as
pre-existing/out-of-scope in PR #36's REPORT.

## Branch-point
Stacked on `feat/seller-facing-and-platform-growth` (tip `6573b12a`; PRs #34/#35/#36
merged). `main` still at #30. Reproduced on this base:
`go vet -tags=integration ./internal/e2e/` → `delivered_multi_seller_test.go:175:45:
undefined: cashback.ReferenceInterestRateBpsConst`.

## §2.1 Reference sites (3, all in `internal/e2e/`)
| File:line | Use | Asserted? |
|---|---|---|
| `order_to_cashback_test.go:273-281` | recompute v6 monthly, assert live plan row `== 145` | yes |
| `kargo_to_cashback_test.go:424-426` | assert live plan row `== v6 formula` | yes |
| `delivered_multi_seller_test.go:171-175,283` | compute `wantMonthly` (v6), assert plan row | yes |

## §2.2 Definition / deletion
- Not present in `internal/cashback/` today. Only a `ReferenceInterestRateBps`
  **field** survives (`domain.go:39`, "v6 legacy field kept for backward compat
  with the HTTP API").
- **Deletion commit: `127f3f07 feat(cashback): implement v8 ACCELERATED MODEL`.**
  It removed `const ReferenceInterestRateBpsConst = 5000` (the v6 LOCKED perpetual
  reference rate) and replaced the whole formula with the v8 accelerated
  amortization model: `const CashbackK int64 = 156000` + `ComputePlanTerms`.
  The cashback package's own property tests were migrated to v8; these 3 `e2e`
  sites were missed.

## Chosen fix shape — **Option C / "B" (migrate consumers to v8)** [owner-approved]
Not Option A (the constant was deliberately deleted, not lost): restoring it would
compile but leave the assertions comparing the **live v8 plan row** against **dead
v6 math** (v8 row ≠ 145). There is no equivalent constant — the v8 engine computes
monthly from `(priceMinor × commissionBps) / CashbackK`.

**Fix:** remove all 3 `ReferenceInterestRateBpsConst` references; compute the
expected monthly via the engine's own `cashback.ComputePlanTerms(priceMinor,
commissionBps).MonthlyAmountMinor` — the exact function the plan-creation path
uses (`service.go:63` → stored as `MonthlyAmountMinor`). This makes the suite
**compile and the assertions correct (pass)**. No engine/business-logic change,
only the test expected-value source.

Per-site inputs (matching what the consumer resolves: `priceMinor` = Σ unit×qty,
`commissionBps` = items[0]):
- order_to_cashback: price=50000, bps=700 → 224 (was v6 145).
- kargo: price=100000, bps=700 → 448 (was v6 291).
- multi-seller: price=160000 (50000+30000+80000), bps=commBpsA=700 (item order
  A1,A2,B1) → 717 (was v6 totalComm-based).

Helper vars `commA1/commA2/commB1/totalComm` in multi-seller become unused after
the v6 calc is removed → deleted in the same edit.

## Out of scope / Backlog
- The "0 payment rows at plan creation (v6 perpetual)" assertions in these tests
  are a **separate** v6→v8 staleness, not the compile error. Untouched here; if
  they fail at runtime under v8, that's a follow-up (v8 may pre-create the
  schedule). Documented in REPORT.
- `make verify` does not gate the integration-tagged e2e build (vet/test run
  without the tag) — adding that gate is explicitly out of scope (Backlog).

## No parity change
Operational build fix.

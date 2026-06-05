# P-032 (price-update lifecycle) + P-030-PDP (PDP display) — discovery

> Bundled close: P-032 adds the missing variant price-**update** path (so #92's
> `variants_price_history_trg` actually accrues history), and P-030-PDP extends the
> product-detail read with `lowest_30d` so the pre-built `PdpPriceBlock` slot renders.
> Together they activate the dormant card line (#93) and the PDP line. Paths are
> `internal/catalog/` + `cmd/core-svc/` (the prompt's `services/core-svc/...` is wrong).

## 1. P-032 — the update path is SELLER-scoped, not admin

The prompt assumed an "admin endpoint." Discovery: the established write-auth model is the
**seller role**, and that is the correct owner of a price change in a marketplace.

- `internal/identity/middleware/seller.go`: `RequireSellerRole(lookup)` resolves the caller's seller
  binding (403 if none) and puts `seller_id` in ctx; `middleware.SellerIDFromCtx(ctx)` reads it.
- `cmd/core-svc/main.go` already gates the seller dashboard with `requireAuth(requireSellerRole(...))`
  (returns, questions). New endpoint follows the same wrap.
- Ownership is enforced **in SQL**: `UPDATE … WHERE id=$variant AND product_id IN
  (SELECT id FROM catalog_schema.products WHERE seller_id=$ctxSeller)` — atomic, no fetch-then-check
  race, no cross-seller leakage (0 rows → 404).
- **Idempotency:** `PUT` is naturally idempotent (re-applying sets the same value; #92's
  `IS DISTINCT FROM` trigger guard dedupes history), but CLAUDE.md §4.4 requires the header on every
  public POST/PUT — reuse `requireIdempotencyKey` (as `handleCreateProduct`/`handleAddVariant` do).
- **History:** the #92 trigger fires on `UPDATE OF price_minor, original_price_minor` automatically.
  **Do not** write `variant_price_history` directly (anti-goal) — always go through the variant UPDATE.

→ **Outcome B (seller-scoped), no new auth infra.** Endpoint: `PUT /seller/variants/{id}/price`,
body `{price_minor, original_price_minor?}`.

### Validation (service layer)
- `price_minor > 0`.
- if `original_price_minor` set: `> 0` and `>= price_minor` (the strikethrough "was" price; `<` is
  nonsensical). Omitted ⇒ NULL (PUT replaces the price state — clears any discount).
- **Not enforced here (legal/policy, out of scope):** that `original_price_minor` is *substantiated*
  by 30-day history (the deeper Omnibus question P-030 flagged) — that needs legal sign-off.

### Order/ledger safety
Variant price feeds seller-payout + cashback **at order time via snapshot** (CLAUDE.md §4.7/§4.8), so a
price update only affects FUTURE orders — existing orders/plans are untouched. No ledger interaction.

## 2. P-030-PDP — needs PER-VARIANT lowest_30d (not product-level)

The prompt said "add `Product.lowest_30d_price_minor`." **That is wrong for the PDP.** The card uses
`ProductSummary.lowest_30d` = product-level `MIN` across variants — correct there because the card shows
the *cheapest-variant* price. But the **PDP shows a specific selected variant**; a product-level MIN
would display a value belonging to a *different, cheaper* variant (misleading once prices diverge).

→ **Per-variant** `lowest_30d`: extend `loadVariants` (`repository.go`) with the 30-day MIN subquery
keyed on `variants.id`, add `Variant.Lowest30dPriceMinor *int64`, surface it on the spec `Variant`
schema, and have the PDP pass `selectedVariant.lowest30dPriceMinor` to the existing
`PdpPriceBlock.lowestIn30DaysMinor` slot. **Outcome A** (read-only extension).

`GetByID` returns `(Product, []Variant, …)`; the per-variant field rides the variants list — no change
to the `Product` type needed. The PDP display condition mirrors #93's card: show when a reduction is
announced and `lowest_30d < price` (today `==`, so dormant).

## 3. Decision matrix

| Objective | Outcome | Strategy |
|---|---|---|
| P-032 lifecycle | **B (seller-scoped)** | `PUT /seller/variants/{id}/price`, ownership-in-SQL, idempotency, trigger-backed history |
| P-030-PDP | **A (read-only, per-variant)** | per-variant `lowest_30d` on `loadVariants`/`Variant`/spec; PDP wires the existing slot |

## 4. Activation

Once a seller updates a price, the trigger writes history; thereafter any product/variant whose
`lowest_30d < current` renders the line — **card (#93) activates automatically** (no mobile change), and
the PDP renders via this PR's wiring. Until a price actually moves, both stay dark (honest #92 posture).

## 5. Out of scope (anti-goals)

Admin/cross-seller price tooling; price-history inspection UI; price-change notifications; enforcing
original-price-vs-history compliance (legal); bulk import; P-007/P-031/chi-square. No new migration
(#92's table/trigger are reused).

## 6. Commit plan

1. this doc.
2. repo `UpdateVariantPrice` (seller-scoped, ownership-in-SQL) + Repository iface.
3. service `UpdateVariantPrice` + Service iface + validation + typed errors.
4. handler `handleUpdateVariantPrice` (seller-gated, idempotency) + route.
5. PDP backend: per-variant `lowest_30d` (`Variant` field + `loadVariants` subquery/scan).
6. spec (new endpoint + `Variant.lowest_30d_price_minor`) + regen both clients.
7. mobile PDP wiring (`PdpPriceBlock` consumes `selectedVariant.lowest30dPriceMinor`).
8. tests (lifecycle integration + per-variant lowest_30d integration + PDP widget).
9. docs closure — audit (P-032 + P-030-PDP RESOLVED; P-030 end-to-end), financial-core convention, ROADMAP, REPORT.

# PDP Feature Batch — PD-02 · PD-03 · PD-04 · PD-09 (scoping)

Four banked PDP items in one lane (they share the PDP screen widget; separate
lanes would collide). Scope is re-derived from the original DEFER rationale in
`docs/internal/pdp-probable-resolution.md` + `docs/audits/TRENDYOL_PARITY_PDP_AUDIT.md`
+ `CUTOVER_LEDGER.md`. Read-path-real (the cart-stub lesson #176): each item is
wired to a source that actually serves the data — no fabrication.

## Per-item scope, footprint, and discovery shifts

### PD-02 — variant swatches — **FE-only** (no backend/codegen/migration)
- **Deferred scope (audit):** text chips, not colour swatches; deferred to PLP-13
  Ph2 expecting a "per-variant colour→swatch signal".
- **Discovery shift:** the variant **already serves `color`** (spec `Variant.color`,
  the real TR colour name e.g. "Kırmızı"). A swatch is a *presentation* of that real
  field — render a colour chip via a **TR colour-name → hex** map; unknown names fall
  back to the existing text chip. Doesn't need the PLP-13 Ph2 attribute model for
  the common case; non-name colours stay text (flagged, not faked).
- **Source:** `Variant.color` (already on the PDP read-path, the same variant
  resolution PLP-17/cart use). **Footprint:** mobile only.

### PD-03 — basket-discount "Sepette %X" on the PDP — **backend + codegen, NO migration**
- **Deferred scope (audit):** the flat `Product` (`GET /products/{id}`) has **no**
  `basket_discount_pct` field (only the card's `ProductSummary` does) → needs
  spec/codegen + backend; *not* display-only (audit's "display-only" was stale).
- **Discovery shift / §4 safety:** the discount is **already charged** (CT-09,
  migration 0091 — `products.basket_discount_pct` snapshotted onto
  `order_items.basket_discount_pct` at order time). Surfacing it on the PDP is
  **display of the already-charged snapshot** → `display==charge` holds because the
  PDP reads the *same* `products.basket_discount_pct` the order charges. **No client
  money math, no new pricing path → NOT a §12 trigger; no split needed.**
- **Plan:** add `basket_discount_pct` to spec **Product** + `catalog.Product` +
  `GetByID` product SELECT + `productDetailJSON`; mobile renders the "Sepette %X"
  pill on the price block (mirrors the PLP card's pill). **Contract test** the
  field + assert PDP pct == the charged source (display==charge). **No migration**
  (column exists since 0091).

### PD-04 — seller rating on the PDP seller card — **backend + codegen, NO migration**
- **Deferred scope (audit):** "no seller-rating aggregate yet → DEFER (backend)".
- **Discovery shift:** the aggregate **already exists** —
  `catalog.SellerStorefrontReader.SellerReviewSummary(sellerID) → (avg, count)`
  (the storefront `GET /sellers/{slug}` already renders it). The audit's "no
  aggregate" is **stale**. PD-04 just surfaces it on the PDP.
- **§5:** PDP is `catalog`; the rating aggregates `catalog` reviews by seller → the
  `SellerReviewSummary` carrier is an in-process `catalog` read (no cross-schema
  JOIN; the seller *name/official* still come from `sellerSvc`).
- **Plan:** add `seller_rating_avg` (nullable) + `seller_rating_count` to spec
  Product + `productDetailJSON`; handler calls `SellerReviewSummary(p.SellerID)`;
  `PdpSellerCard` renders stars + count with a graceful **empty state** (count 0 →
  no rating shown). **Contract test.** **No migration.**

### PD-09 — sticky add-to-basket bar — **FE-only polish** (NEEDS-VISUAL)
- **Deferred scope:** the sticky buy-bar feature is **already RESOLVED** (#203,
  `PdpStickyBuyBar` + mobile `PdpStickyCta`); the residue is the NEEDS-VISUAL "feel".
- **This lane's scope:** overlay polish only — **safe-area** insets, **z-order**
  (the bar is an overlay above content), **no content occlusion** (bottom scroll
  padding so the last content clears the bar), scroll behaviour. No redesign, no
  sticky-gallery-vs-buy-box change (that stays NEEDS-DECISION). **Footprint:** mobile.

## Footprint summary (for the run matrix)

| Item | Backend | Codegen | Migration | Money path |
|---|---|---|---|---|
| PD-02 swatches | no | no | no | no |
| PD-03 basket-discount | yes (`Product.basket_discount_pct`) | **yes** | **none** | display-only of charged snapshot (§4-safe) |
| PD-04 seller rating | yes (`SellerReviewSummary` carrier) | **yes** | **none** | no |
| PD-09 sticky bar | no | no | no | no |

- **Migrations: NONE.** The reserved block 0100–0102 is **unused** — both PD-03 and
  PD-04 reuse pre-existing data (the CT-09 column + the storefront review aggregate).
- **Codegen: PD-03 + PD-04** add three fields to the spec `Product`
  (`basket_discount_pct`, `seller_rating_avg`, `seller_rating_count`) → Go + Dart
  regen (this lane owns the Wave-1 regen).
- **i18n:** `pdp.*` namespace; PD-03 (finance) gets DE/AR too, PD-02/04/09 TR/EN
  (per the #218 precedent: finance copy is 4-locale, console/UI copy TR/EN).

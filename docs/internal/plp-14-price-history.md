# PLP-14 — price-history filter ("Fiyat Geçmişi") — design + defer

> Trendyol's "Fiyat Geçmişi / Son N günde fiyatı düşenler" filter. **Feasible
> (Outcome A) — the data + the exact pattern both exist.** Deferred only because
> the build is a full OpenAPI-codegen vertical; this doc makes it a quick
> follow-up. Track C of the PLP-completion work order.

## Data — feasible

- `catalog_schema.variant_price_history` (migration **0083**): `product_id`,
  `price_minor`, `effective_at`, indexed `vph_product_effective_idx
  (product_id, effective_at DESC)`. Already powers the on-card lowest-30d
  (`productSummarySelect`'s `lowest_30d_price_minor` subquery). A **server-side**
  "price dropped" predicate is straightforward over this table.

## The filter (proposed)

"**Fiyatı düşenler**" = the current variant price is **below** a price the product
carried earlier in the window → a genuine drop:

```sql
-- in appendProductFilters, when f.PriceDropped is true:
AND EXISTS (
  SELECT 1 FROM catalog_schema.variant_price_history vph
  WHERE vph.product_id = p.id
    AND vph.effective_at >= now() - INTERVAL '30 days'
    AND vph.price_minor > v.price_minor      -- v = the cheapest live variant (LATERAL)
)
```
Single-schema (`catalog_schema` only — **§5-safe**), index-served. (A days-param
variant — 10/14/30 — is a trivial extension; ship the 30-day toggle first.)

## Why deferred (the build is a codegen vertical)

Mirrors the **proven P-028 pattern** (`free_shipping`/`in_stock` query params), so
it's low-risk but **wide**:
1. **OpenAPI** `api/openapi.yaml`: add a `price_dropped` boolean query param to
   `listProducts` (+ search), mirroring `free_shipping` (`:1841`).
2. **Codegen** `make api-gen` (Docker `openapi-generator` v7.10.0 → Go API +
   Dart `mopro_api`) — a large generated diff gated by `build_runner`,
   `dart analyze (mopro_api)`, `api-lint`, `contract-test`.
3. **Backend:** thread the param → `ProductFilter.PriceDropped` →
   `appendProductFilters` WHERE (above) → `ListProductsByCategory` +
   `SearchProductsSummary`.
4. **Dart:** `PlpFilters.priceDropped` + `PlpFiltersCodec` + provider wiring +
   a toggle in the desktop `FilterPanel` and the mobile `PlpFilterSheet`
   (mirror the free-shipping `SwitchListTile`) + a removable chip.
5. **i18n** (`plp.filter_price_dropped`), **tests** (a backend filter integration
   test + a UI toggle test), **goldens** (the 8 `plp_sidebar_*` flip — a new
   sidebar toggle).

That's a single, self-contained feature PR; bundling its codegen + golden churn
into a multi-track batch risks a noisy/partial landing (anti-goal: don't ship
half-built). **Verdict: ship this design; build as a focused follow-up PR.**

## Status

Audit PLP-14 → **DEFER (feasible, design-ready)**; ledger §4c. Not infeasible —
this is "ready to build," gated only on running the codegen vertical cleanly.

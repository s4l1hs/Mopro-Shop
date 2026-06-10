# PLP-13 phase 1 — attribute model + `renk` facet (discovery)

> Executes **phase 1** of `docs/internal/plp-13-attribute-model.md` (#149). Per
> §1.3/§5 the phase-1 slice is narrowed to **one attribute — `renk` (colour) —
> end-to-end**, and split into a **backend PR (this)** + a **deferred UI PR**.

## Phase-1 slice (confirmed + narrowed)

The #149 Phase 1 = the 3 tables + backfill `renk` (from `variants.color`) **and**
`depolama` (from `products.specs`) + one facet surface + filter + accordion.

**Narrowed to `renk` only** (defer `depolama` + all other attributes to Phase 2):
- `variants.color` is a **structured, populated** source (apparel carries it; the
  PDP-seed lane gave MP-S001 Siyah/Beyaz/Lacivert). `depolama` needs `products.specs`
  JSONB extraction **and there is no phone in the seed** (`specs` is `{pages,isbn}`
  for books) — low value, higher risk → Phase 2.
- `renk` is a first-class Trendyol facet (colour filter) and a real spec row.

## Schema (catalog_schema only — §5-safe) — migration 0089

`attribute_keys` (slug/name_tr/name_en/data_type) · `category_facets`
(category_id soft-ref, attribute_key_id, display_order, searchable, PK both) ·
`product_attributes` (surrogate id, product_id soft-ref, attribute_key_id,
value_text, value_num; `UNIQUE(product_id, attribute_key_id, value_text)`; indexes
`(attribute_key_id, value_text)` for aggregation + `(product_id)` for lookup).
Migration also seeds the **fixed** `attribute_keys` row `renk` (deterministic) +
grants to `catalog_user`.

**Discovery shift — backfill is a SEED, not a migration step.** In dev, migrations
run on an **empty** DB and the catalog seed populates `variants` afterwards, so a
migration-time `INSERT … SELECT FROM variants` would capture nothing. The backfill
of `product_attributes` (from `variants.color`) + the `category_facets(renk)`
seeding therefore live in a dev seed `scripts/seed/data/attr-extras.sql` (applied
after `make seed`, mirroring `pdp-walk-extras.sql` / `plp-density-extras.sql`).
In prod the same backfill runs as a one-off data step at the deferred cutover.

## Facet aggregation endpoint — `GET /categories/{id}/facets`

**Discovery shift:** brands have **no** aggregation endpoint today — `FilterPanel`
derives brands from the current result set (its own comment notes this) — so this
is the **first** real facet-aggregation surface. `GET /categories/{id}/facets`
(+ the same brand/price/rating/attr filters) returns, per `category_facets`
attribute over the PLP-12 subtree, `{slug, name, values:[{value, count}]}`
(`count(DISTINCT product_id)`). Reuses the `WITH RECURSIVE` subtree +
`appendProductFilters` already in `ListProductsByCategory`. §5-safe (single schema;
`ref_schema.categories` is the allowed cross-module read).

## Filter param — `attr=<slug>:<value>` (repeated)

`ProductFilter.Attrs map[string][]string`; the handler parses repeated
`?attr=renk:Siyah&attr=renk:Beyaz` → an `EXISTS (… product_attributes …)` per slug
in `appendProductFilters` → threads into `ListProductsByCategory` **and**
`SearchProductsSummary` (search inheritance is free). Generic over slugs (Phase 2-ready).

## PDP specs tab (PD-01) needs PER-PRODUCT attributes

The facet endpoint is per-category; the specs tab needs the **product's** attributes.
So add an **`attributes`** array (`[{slug, name, values[]}]`) to the **`Product`**
(`GET /products/{id}`) response — the #158 **live-handler contract test** then
validates it automatically. The mobile `_StubTab` (`product_detail_screen.dart:882`,
used at the specs tab) is replaced in the UI PR.

## PR split

- **PR 1 — backend (this):** migration 0089 + `attr-extras.sql` seed + facet
  endpoint + `attr` filter (PLP + search) + `Product.attributes` + spec + Go/Dart
  codegen + integration test (facet aggregation + filter) + extend the live-handler
  contract test (facets endpoint + Product.attributes). Independently verifiable
  (curl the endpoint; contract test validates schemas).
- **PR 2 — UI (deferred, scoped):** `FilterPanel`/`PlpFilterSheet` `renk` accordion
  (mirror `PlpBrandFacet`, driven by the facet buckets) auto-inheriting to search +
  `PlpFilters.attrs`/codec/chips/provider wiring; PDP specs tab reading
  `Product.attributes` (replaces `_StubTab`, closes PD-01 for the slice); i18n;
  widget tests; goldens (Linux). Per §7.3 the facet + specs ship together in PR 2.

## Deferred (Phase 2+, per #149): `depolama` + other `specs` attributes, value
normalization, the seller attribute-write path, numeric/range facets, facet caching.

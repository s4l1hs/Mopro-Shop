# PLP-13 Phase 2 — more attribute types — discovery + DEFER

> Goal: light up more attribute facets (depolama/ekran/RAM …) via the generic
> phase-1 infra (no codegen, no UI). **Outcome: the infra is confirmed generic
> (the payoff is real), but there is no clean, semantically-correct data source
> for a second attribute yet → backfill DEFER'd** until the attribute write-path
> lands. Verified on `feat/plp-13-phase2`.

## ✅ The phase-1 infra IS generic (payoff validated)

- **Endpoint/repository:** `FacetsByCategory` (`repository.go:621`) walks
  `category_facets` for the category's **subtree** (no `slug='renk'` filter),
  joins `attribute_keys` + `product_attributes`, and returns **every** registered
  facetable attribute grouped by slug — attribute-agnostic.
- **UI:** `PlpAttributeFacet` takes any `Facet{slug, name, values}` and renders it;
  `FilterPanel` loops one section per facet; PDP specs tab renders
  `Product.attributes` generically.

→ **The moment a (key + `product_attributes` data + `category_facets`) triple
exists, the attribute surfaces on PLP + search + PDP with ZERO code.** That is the
phase-1 payoff, and it is genuinely in place.

## 🚩 But there is no clean phase-2 data source (the blocker)

The #149 plan assumed `products.specs` JSONB as the source for depolama/ekran/RAM.
**It does not exist** — `catalog_schema.products` has no `specs` (or any attribute)
column (columns: id, seller_id, category_id, brand, currency, locale, status,
timestamps, rating_*, free_shipping). The only structured attribute columns are:

| Column | Phase-1 use | Phase-2 viability |
|---|---|---|
| `variants.color` | → `renk` ✅ (semantically correct) | done |
| `variants.size` | — | **not viable**: semantically *size*, not storage/RAM; **heterogeneous** (apparel `L/M`, dimensions `35x28x10cm`/`100cm`, volume `50ml`, even phone storage `256GB` mis-filed here) and **sparse** (1–2 products/category outside the artificial `elektr-kea` density seed). |

- A `depolama` from `variants.size` would mean **deriving storage from a column
  that means size** — real-looking only because the seed mis-filed `256GB` there;
  not a correct/robust source (it would misfire in prod). Rejected (the renk
  derivation was *semantically correct* color→renk; size→depolama is not).
- A `beden` (size) facet is semantically correct, but the size data is mixed even
  within apparel-ish categories (`moda-canta` = bag *dimensions*, not beden) and
  too sparse (1 product per clean category) to form a meaningful facet.

→ Per the §1.3 escape hatch ("ship the clean ones + DEFER the messy"): **there are
no clean ones** — color was the only semantically-correct structured attribute,
and it shipped in phase 1.

## Verdict — DEFER (no code, no fabricated data)

Phase-2 attribute types are **blocked on a real attribute source**, which is
exactly the **attribute write-path** (#149 phase 2/3): sellers / catalog ingestion
populate `product_attributes` with correct, typed values per category. That is the
true phase-2 work — *not* backfilling from existing columns (there's nothing
correct left to backfill after `renk`). When that path lands, registering each
type is the trivial (key + `category_facets`) step the generic infra already
supports.

- **No migration / seed / code** here — adding empty `attribute_keys`
  (depolama/ekran/ram) with no data + no `category_facets` would surface nothing
  (the endpoint returns an attribute only when it has data) → inert; left for the
  write-path PR that actually populates them.
- §5-clean (catalog_schema only would have applied); deploys deferred.

## Discovery shifts

1. **The infra is generic** — validated against `FacetsByCategory` + the UI; the
   phase-1 payoff is real (zero-code attribute add).
2. **`products.specs` JSONB never existed** — the #149 phase-2 source assumption
   is wrong; the design doc's `specs` is aspirational.
3. **`variants.size` is not a usable source** — semantically overloaded + sparse;
   the only correct structured attribute (color) was already consumed by renk.
4. **Real phase 2 = the write-path**, not a backfill — DEFER until then.

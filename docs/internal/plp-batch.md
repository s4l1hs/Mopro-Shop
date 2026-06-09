# PLP CONFIRMED-HIGH batch — PLP-04 / PLP-05 / PLP-13 — discovery

> Top of the PLP CONFIRMED-HIGH queue. **PR 1 = PLP-04 + PLP-05** (quick wins);
> **PR 2 = PLP-13** (discovery-gated). Verified on `feat/plp-count-breadcrumb`.

## PLP-04 — visible result count

- The list API already returns `pagination.total` (`PaginationMeta.total`), but
  `ProductsState` (`products_by_category_provider.dart`) **discards it** — it only
  uses `meta.totalPages` for `hasMore`. → **Small surface:** add `total` to
  `ProductsState` + set it in `filtered_products_provider._load`.
- **Render:** the PLP screen — mobile in the `CatalogShell` filter/sort bar,
  desktop in the `_buildWide` chip-row. Live (the provider refetches on filter
  change, so `total` updates). i18n: one new key (`plp.result_count`).

## PLP-05 — breadcrumb trail

- **No API change needed.** `Category` already has **`parentId`**, and
  `categoriesProvider` holds the full tree. Build the ancestry client-side: walk
  `parentId` from the current category to the root → `[root … current]`.
- **Render:** a `PlpBreadcrumb(categoryId)` widget — `Anasayfa › Root › … ›
  Current` (ancestors tappable → `/categories/{id}`, current is plain). Desktop
  prominent (above the chip row); mobile a compact horizontally-scrollable row.
  i18n: `plp.breadcrumb_home`.

## PLP-13 — attribute facets → **Outcome C (DEFER)**

Classified before writing code (§1.3):
- **`catalog_schema.variants`** has structured **`color` + `size`** TEXT columns —
  but they're **not** accepted as filter params by `listProducts` (only brand /
  rating / price / free-shipping / in-stock), and they're **sparse/empty** for
  most seed rows (defaults `''`).
- **`products.specs`** is an **opaque JSONB blob** (`0061`, default `{}`) with
  **arbitrary per-category keys** (e.g. `pages`/`isbn` for books) — no schema says
  which keys are facetable per category, no GIN/path index, no value normalization.
- **No** normalized attribute / option / facet table exists anywhere; **no**
  facet-aggregation (values + counts) endpoint.

Trendyol's deep, **category-aware** attribute stack (storage/RAM/screen/condition/
camera…) requires a structured attribute model + per-category facet config +
an aggregation surface — a **schema/data-modeling effort**, not a UI add. Building
JSONB-key faceting on opaque `specs` would be the "fragile attribute store" the
anti-goals forbid. **→ DEFER PLP-13** as a backend track in `CUTOVER_LEDGER.md`;
no PR-2 code. (color/size are a thin B-footnote: real columns, but unfiltered +
sparse → surfacing them alone doesn't deliver the PLP-13 parity and still needs a
full filter-param + aggregation build.)

## Goldens

- The desktop PLP goldens `plp_sidebar_{no_filters,with_filters}_{1024,1440}_
  {light,dark}` (8) render `CategoryProductsScreen` → **count + breadcrumb will
  flip all 8** (predict). No mobile PLP golden exists. Regen on Linux, reconcile.

## Plan

- **PR 1** (`feat/plp-count-breadcrumb`): `ProductsState.total` surface + count
  render (PLP-04); `PlpBreadcrumb` widget mounted mobile + desktop (PLP-05); i18n;
  goldens; audit PLP-04/05 → resolved.
- **PR 2:** **none** — PLP-13 DEFER'd (Outcome C); rationale → ledger + audit.

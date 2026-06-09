# Catalog backend vertical — SE-08 + SE-03 + PLP-14 (discovery)

> Parallel **Session 2** discovery doc. Two catalog-backend items: **SE-08**
> (search relevance via `ts_rank`) and **PLP-14** (price-history filter), plus the
> **SE-03** handshake (`total` for Session 1's search count). Disjoint file set
> from Session 1 (search UI). This session is the **sole** spec/codegen owner this
> round.

## SE-08 — relevance ranking (backend-only, no contract change)

- **Where ordering happens:** `internal/catalog/repository.go`.
  `SearchProductsSummary` (`:521`) currently calls the **shared** `appendOrderBy`
  (`:431`), so an unspecified sort falls through `orderByClause("")` (`:411`) to
  `ORDER BY p.id DESC` — i.e. **id order, not relevance**. That's the SE-08 gap.
- **Data is ready:** `product_translations.search_vector` is a `to_tsvector('simple', …)`
  generated column with a GIN index (migration **0057**). The search WHERE already
  binds the query at `$1` (`t.search_vector @@ plainto_tsquery('simple', $1)`), so
  `ts_rank(t.search_vector, plainto_tsquery('simple', $1))` reuses the same bound
  arg — **no new placeholder, no new index**.
- **Plan:** a search-specific `appendSearchOrderBy` that, in priority order,
  honours (1) a bestseller ranking (`PopularIDs` → `array_position`, unchanged),
  (2) an **explicit** sort token (price/newest/cashback — same clauses as listing),
  else (3) **relevance** `ORDER BY ts_rank(...) DESC, p.id DESC`. Listing
  (`ListProducts*`) keeps `appendOrderBy` → id-order default, untouched.
- **No sort-token / contract change.** Relevance is the *implicit default* for
  search (`recommended`), so no new enum value and **no codegen** for PR1. The
  `FilterSort` enum stays `[recommended, bestseller, newest, price_asc, price_desc,
  cashback_desc]`; for **search**, `recommended` now means relevance.

## SE-03 — search result count (`total`) — ALREADY SATISFIED

- **Discovery shift:** the contract + handler **already expose `total`.** The
  `Search` 200 response uses `PaginationMeta` (`openapi.yaml`), whose `total` is a
  **required** field; `handleSearch` (`cmd/core-svc/catalog_handlers.go:174`) calls
  `SearchSummary` (which returns the `count(*) OVER()` window total) and renders it
  via `buildProductListResponse` → `pagination.total`.
- **Therefore no backend change.** Session 1 reads `resp.data.pagination.total`
  (nullable-guarded) for the "X ürün" count. This doc records the handshake as
  *met by the existing envelope*; PR1 carries only the SE-08 ordering change + the
  audit note.

## PLP-14 — price-history ("Fiyatı düşenler") filter — full codegen vertical

Per `docs/internal/plp-14-price-history.md`. Mirrors the proven P-028
`free_shipping`/`in_stock` boolean-param pattern end-to-end.

- **Data (ready, §5-safe):** `catalog_schema.variant_price_history(product_id,
  price_minor, effective_at)` + index `vph_product_effective_idx` (migration 0083).
  Single-schema; **no migration/index needed**.
- **WHERE clause** (in `appendProductFilters`, `repository.go:372`, when
  `f.PriceDropped` is true):
  ```sql
  AND EXISTS (
    SELECT 1 FROM catalog_schema.variant_price_history vph
    WHERE vph.product_id = p.id
      AND vph.effective_at >= now() - INTERVAL '30 days'
      AND vph.price_minor > v.price_minor   -- v = cheapest live variant (LATERAL)
  )
  ```
  `v` is the LATERAL cheapest-variant alias already in `productSummarySelect`
  (`:355`); the predicate is index-served and single-schema.
- **Backend thread:** `ProductFilter.PriceDropped *bool` (`domain.go`) →
  `appendProductFilters` EXISTS → flows through `ListProductsByCategory` /
  `ListProducts` / `SearchProductsSummary` (all share the helper) →
  `parseProductFilter` (`catalog_handlers.go:191`) parses `price_dropped=true`.
- **Spec:** add `FilterPriceDropped` (`price_dropped` boolean query param) to
  `ListProducts` + `Search`, mirroring `FilterFreeShipping` (`openapi.yaml:1840`).
- **Codegen (`make api-gen`):** oapi-codegen (Go: `internal/api/gen/**`) + Docker
  `dart-dio` (`mobile/packages/mopro_api/**`). Gated by `api-check-sync`.
- **Dart:** `PlpFilters.priceDropped` + `copyWith`/`==`/`hashCode`/`isEmpty`/
  `activeChipCount` (`plp_filters.dart`) → `PlpFiltersCodec` (`drop=down` key,
  `plp_filters_codec.dart`) → provider wiring (`filtered_products_provider.dart:65`,
  `search_provider.dart:109`: `priceDropped: f.priceDropped ? true : null`) →
  `FilterPanel` `_priceDropped` `SwitchListTile` (mirror `_freeShipping`,
  `plp/widgets/filter_panel.dart:245`) → removable chip
  (`plp/widgets/plp_filter_chips.dart`).
- **i18n:** `plp.filter_price_dropped` (tr-TR + en-US).
- **Tests:** a backend filter integration test (mirror `filter_integration_test.go`)
  + a codec/model round-trip. **Goldens:** the `plp_sidebar_*` set flips (a new
  sidebar toggle) — regen on Linux (predict-then-verify), per anti-goal §7.4.

## Sequencing

- **PR 1 — SE-08 (+ SE-03 note):** backend ordering only; no codegen. Small, no UI.
- **PR 2 — PLP-14:** the codegen vertical (one clean `make api-gen` pass).
- Escape hatch (§1.3/§5): if PLP-14's facet UI proves heavy, ship its
  backend+param first, the facet UI second. PR1 lands regardless.

## Ownership / anti-goals

- OWNS: `api/openapi.yaml`, generated Go+Dart clients, `internal/catalog/**`,
  `mobile/lib/features/catalog/**` (incl. `plp/widgets/filter_panel.dart`).
- MUST NOT edit `mobile/lib/features/search/**` (Session 1's search UI). The
  search **backend** query (SE-08) and `features/catalog/providers/search_provider.dart`
  are in scope; the search *screens* are not.

# SE-06 — Structured brand + product search suggestions (discovery)

Lane C, `feat/search-suggestions-se06`. Goal: the search autocomplete dropdown
returns structured **brand + product** suggestions as the user types, tappable
through to the brand PLP / product PDP — matching Trendyol's autocomplete. Today
the dropdown shows only recent + trending + category shortcuts.

## `/search/suggest` — current shape

- **Spec:** `api/openapi.yaml` defines `SearchSuggest` (`GET /search/suggest?q=`)
  returning `{ suggestions: string[] }` — pure query-completion. The generated
  Dart `SearchApi.searchSuggest()` returns `SearchSuggest200Response`
  (`suggestions: List<String>`).
- **Backend:** **the endpoint is not wired.** `cmd/core-svc/main.go` routes
  `GET /search`, `GET /search/trending`, but **no** `GET /search/suggest`. The
  oapi-codegen strict-server types for `SearchSuggest` exist in
  `internal/api/gen/` but core-svc hand-wires plain `http.HandlerFunc`s (it does
  **not** use the strict server interface), so the generated suggest handler is
  dead code. Net: the endpoint "exists" in the spec + generated clients but
  serves nothing. (Matches Session 1's "exists and is unused" note.)

So the current surface is query-completion-only and unwired — **not** usable
structured brand/product data.

## Data model — both suggestion kinds are single-schema (§5-safe)

Search is **Postgres-backed** (not a direct Meili call): `GET /search` →
`catalog.Service.SearchSummary` → `repo.SearchProductsSummary`, which matches on
`catalog_schema.product_translations.search_vector` (+ `title ILIKE`) and joins
`catalog_schema.products` / `variants`.

- **Brand** is a plain `text` column `catalog_schema.products.brand` (no brand
  entity / brand PLP). A "brand PLP" = the PLP/search filtered by `brand=<name>`
  (the `FilterPanel` + `SearchSummary` already support the `brand` filter). So a
  brand suggestion routes to `/search?q=<brand>` (or a brand-filtered listing).
- **Product** suggestion = a product row → PDP by `id`.

Both derive entirely from `catalog_schema` (`products` + `product_translations`
+ `variants`). **No cross-schema JOIN** — §5 satisfied.

- Brands: `SELECT brand, count(*) FROM catalog_schema.products
  WHERE status='active' AND brand <> '' AND brand ILIKE $1 || '%'
  GROUP BY brand ORDER BY count(*) DESC, brand LIMIT $2` — a new lightweight
  `Repository.SuggestBrands`.
- Products: reuse `Repository.SearchProductsSummary(q, locale, ProductFilter{},
  offset=0, limit=N)` — already returns `ProductSummaryRow` (id, title, brand,
  cover image key, price, …). No new product query needed.

## Dropdown widget + host (to extend)

- `mobile/lib/shell/search_suggestions_dropdown.dart` — `SearchSuggestionsDropdown`,
  pure presentation: three optional sections (recent / trending / categories),
  empty sections collapse. (Session 1's "lives in `features/catalog/`" note was
  imprecise — the desktop dropdown is under `lib/shell/`. The mobile full-screen
  search empty/no-results body in `features/catalog/screens/search_screen.dart`
  shows the same recent/trending/category content as chips.)
- `mobile/lib/shell/web_search_pill.dart` — `WebSearchPill` hosts the dropdown in
  an `AnchoredOverlayPanel`. Today it does **not** feed the typed text to a
  suggestions query; `onChanged` is unused. Needs: debounced (300 ms, the
  existing client cadence) query → suggestions provider; brand/product sections
  shown when the query is non-empty, recent/trending/categories when empty.
- Mobile (`< 600` width) uses `SearchInput` + `search_screen.dart`; the
  as-you-type dropdown is the desktop-header surface. Mobile already triggers a
  live results grid on type. This lane wires the **dropdown** (desktop pill) per
  the audit's `SearchSuggestionsDropdown` finding.

## Verdict — **Outcome B (spec + codegen + backend + UI)**

The endpoint returns only query-completion (`string[]`) and is unwired, so a new
response surface is required. Plan:

1. **Backend** (independent of codegen — core uses manual handlers): catalog
   `BrandSuggestion` / `SuggestResult` domain types, `Service.Suggest`,
   `Repository.SuggestBrands`; `handleSearchSuggest`; wire `GET /search/suggest`.
2. **Codegen:** `api/openapi.yaml` `/search/suggest` 200 → new
   `SuggestResponse { brands: BrandSuggestion[], products: ProductSummary[] }`
   (reusing the existing `ProductSummary` component for products); `make api-gen`
   (Go models/server + dart-dio client) committed with the spec (pre-commit
   `api-check-sync` requires them staged together).
3. **UI:** debounced suggestions provider → generated `SearchApi.searchSuggest`;
   brand + product rows in `SearchSuggestionsDropdown`; tap → PLP / PDP.

### Blast radius / gotchas
- Adding `Service.Suggest` + `Repository.SuggestBrands` breaks every hand-written
  Go fake of those interfaces (catalog `service_test.go`, and the `cart`/`order`
  fake catalog services, incl. `//go:build integration` ones) — only caught by
  `go vet -tags=integration` / `make verify`. Thread the new methods through.
- Changing the spec regenerates ~the Dart client; the `searchSuggest` return
  type changes `SearchSuggest200Response` → `SuggestResponse`. Run
  `flutter analyze` after `make api-gen` (the PLP-14 fan-out lesson).
- Coverage/locale: products use locale-resolved titles via
  `product_translations`; brands/products are status='active' only.

### Coordination note (audit file)
`§4`/`§6` ask to update `TRENDYOL_PARITY_SEARCH_AUDIT.md` (SE-06), but that file
lives at `docs/audits/` which `§0`/`§7` mark **MUST NOT TOUCH (Lane A)**. The
hard anti-goal wins: this lane records SE-06 status **here** and defers the
`docs/audits/` row flip to Lane A / post-merge to avoid clobbering Lane A's walk.
Current audit row (for reference): SE-06 — "no brand/product autocomplete"
(PROBABLE/await-walk). After this lane: brand + product suggestions wired
end-to-end.

### Golden handshake
If the dropdown change flips a *search* golden Lane B also rebaselines, re-run
the rebaseline after Lane B merges. Goldens are regenerated on Linux CI only
(predict-then-verify locally) — not committed from this macOS worktree.

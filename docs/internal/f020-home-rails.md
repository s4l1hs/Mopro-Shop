# F-020 — Home rails contract fix (discovery)

> Three server-driven Home rails (recommended / bestseller / newest) call
> `GET /products?sort=…` **without** `category_id`; the list handler hard-requires
> `category_id` → `400` → those rails render empty regardless of data. Surfaced
> during LOCAL-PHASEB-01.
>
> **TERMINAL: Outcome C (CORRECTED).** The `category_id` `400` was only the *first*
> of two blockers. Fixing it (global list) got the rails a `200`, but they were
> *still* empty on the emulator — because the strict generated `api.listProducts`
> client **cannot deserialize the backend `/products` response at all** (see the
> "Correction" section). Fix = handler global-list **+** repoint the rail provider
> through the shared manual mapper the rest of the app already uses. Verified: all
> three rails populate on the local emulator.
>
> The original "Outcome A, no client change" analysis below is preserved for the
> trail; the Correction section supersedes it.

## What the client does
- `mobile/.../catalog/providers/products_rail_provider.dart`:
  `productsRailProvider(sort)` → `api.listProducts(sort: sort, perPage: 6)` — **no
  `categoryId`**.
- `home_screen.dart` renders one `ProductRail(title, sort)` per rail returned by
  `GET /home/rails` (server-driven config; keys `recommended` / `bestseller` /
  `newest`, mobile caps at 3). Each rail calls the provider above.
- These are **global, catalog-wide** rails — distinct from the rails that already
  work: banners, mood stories, flash-deals, and `/recommendations/home`
  ("Popüler", personalized→popular fallback). "newest" in particular has **no**
  other endpoint that serves it.

## What the handler does
- `cmd/core-svc/catalog_handlers.go:handleListProducts` rejects a missing
  `category_id` with `400 "category_id required"`, then always routes to
  `catalog.ListProductsByCategory` (base `WHERE p.category_id = $1`).
- `applyBestsellerOrder` **already** supports the global case: `categoryID == nil`
  → `analyticsSvc.PopularProductIDs` (global popularity). Only the handler's
  guard blocks the no-category path.
- There is no global product-list repo method — only `ListProductsByCategory`,
  `SearchProductsSummary`, `ListProductsByIDs`.

## What the contract says (decisive)
- `api/openapi.yaml` `GET /products`:
  - `FilterCategoryId` → **`required: false`** ("Scope results to a category").
  - `FilterSort` enum includes `recommended` / `bestseller` / `newest`; its doc
    says **"`bestseller` orders by global popularity (P-029)"**.
  - Responses: only `200 / 401 / 500` — **no `400`** for a missing category.
- The generated **Dart** client types `categoryId` as **optional** (`int?`); the
  client calls `/products?sort=X` exactly as the spec permits.

→ **The spec and both generated clients already model `/products` as a global,
optionally-category-scoped list.** The handler is the *sole* non-compliant piece:
it invented a `category_id required` 400 that the contract never declared. So this
is a **handler bug**, not a client bug and not a contract gap.

## Decision — Outcome A (handler fix), no spec/client regen
Make `handleListProducts` honour its own contract:
- `category_id` **present** → validate exactly as today (reject non-int / `<= 0`),
  route to `ListProductsByCategory`. **Category-scoped validation unchanged.**
- `category_id` **absent** → serve a **global** active-product list with the same
  `sort` + filters, bounded by `per_page` (≤ 50). New `catalog.ListProducts`
  service+repo method reuses `productSummarySelect` with the category predicate
  guarded by a NULL `$1` (`($1::bigint IS NULL OR p.category_id = $1)`), so the
  arg layout and every filter/sort path are shared with the category query.
- `applyBestsellerOrder(ctx, nil, …)` already yields global popularity → the
  bestseller rail works with zero new analytics code.

**Why not Outcome B (repoint/remove client rails):** the three rails are distinct
and server-advertised. `bestseller` overlaps "Popüler", but `recommended` and
especially `newest` have no equivalent working endpoint; repointing would collapse
three rails into duplicates of "Popüler" and drop "new arrivals" entirely — a
worse Home that contradicts the `/home/rails` server config. The contract already
backs the global list, so fixing the handler is both cheaper and more correct.

## Ordering determinism + perf (bounded + indexed)
`orderByClause` is shared, so global ordering is already deterministic:
- `recommended` (default) → `p.id DESC` (PK).
- `newest` → `p.created_at DESC, p.id DESC` — the one global path lacking an
  index. Add a partial index `(created_at DESC) WHERE status='active'` so the
  `LIMIT 6` rail is an index scan, not a full sort (migration `0086`).
- `bestseller` → `array_position($popularIDs, p.id) NULLS LAST, p.id DESC` —
  identical to the existing category bestseller path; `PopularIDs` is capped at
  `bestsellerPopularCap = 200`.
- `price_asc/desc`, `cashback_desc` → supported by the same clause (not used by
  the three rails but valid global sorts).

No cross-schema JOIN added (the only join is `ref_schema.commission_rules`, the
§5-allowed one). Single schema. `count(*) OVER()` supplies `total` for pagination.

## Plan (one commit per concern)
1. This doc.
2. `internal/catalog`: add `ListProducts` (repo + service + interfaces) + update
   all fakes/mocks (Go unit + `//go:build integration`).
3. `cmd/core-svc/catalog_handlers.go`: optional `category_id`; route global vs
   category; keep strict validation when present.
4. Migration `0086_products_active_created_idx` (partial index for global newest).
5. Local verify: rebuild core-svc, re-seed, confirm the three rails populate on
   the emulator. `make verify` green.

No `api/openapi.yaml` change and no client regeneration are required — the
contract is already correct.

---

## Correction (during local emulator verification)

The handler global-list fix landed and `GET /products?sort=…` (no category) now
returns `200` with global data — but the three rails were **still empty on the
emulator**. Root cause, found by walking the device:

- The rail provider used the **generated** `api.listProducts` → a strict
  `ListProducts200Response.fromJson` / `ProductSummary.fromJson`. The backend's
  shared `buildProductSummaryJSON` envelope emits `cashback_preview.
  monthly_amount_minor` (and a `meta` wrapper), but the spec-generated models
  require `cashback_preview.monthly_coin_minor` (and `pagination`). The missing
  required `monthly_coin_minor` makes `fromJson` **throw**, so the call errored
  and the rail hid — independent of the `category_id` fix.
- This is a **pre-existing, app-wide** drift, not new: the **category PLP and
  search** use the same generated `api.listProducts` and are likewise empty
  ("Nothing here yet" on a category). The codebase already worked around it for
  the hand-written endpoints with an explicit mapper,
  `lib/features/catalog/data/product_summary_api.dart::productSummaryFromApi`
  (its own doc-comment calls out this exact `monthly_coin_minor` trap). The
  working recommendations rail uses it; the naive `productsRailProvider` did not.

**Fix applied (F-020 scope = the three rails):**
1. **Handler (backend):** `category_id` optional → global `catalog.ListProducts`
   when absent; strict validation kept when present; migration `0086` index for
   global `newest`. (As planned.)
2. **Rail provider (client):** repoint `productsRailProvider` to fetch the raw
   `/products` response and map via the shared `productSummaryFromApi` — exactly
   how the working recommendations rail consumes the same shape. No reliance on
   the generated `ListProducts200Response`. The `meta`/`pagination` envelope is
   irrelevant on this path (raw-map read), so the backend response shape is left
   **unchanged**.

**Deliberately NOT done here (out of F-020 scope; §1.2 / §7.3 / §7.4):** the
broader backend↔spec reconciliation (make `/products` emit `monthly_coin_minor`
+ `pagination` so the generated client works, then drop the manual mappers) that
would also fix the **category PLP + search**. That touches working surfaces
(recommendations mapper) and the spec/clients — a separate follow-up
(**F-021**, "generated catalog list client ↔ backend shape"). Filed, not fixed.

**Verified:** rebuilt core-svc + reran the app on the Android emulator — the
"Sizin için seçtiklerimiz", "Çok satanlar", and "Yeni gelenler" rails all render
product cards (image + badge + price), bestseller correctly popularity-ordered
(iPhone first). Working rails (banners, stories, flash-deals, Popüler) untouched.

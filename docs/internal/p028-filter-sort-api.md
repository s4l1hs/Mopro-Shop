# P-028 Discovery — Backend filter/sort API

> Discovery for `PARITY_AUDIT P-028` (catalog/search API applies no filter or sort).
> Deliverable for commit 1; the §2 matrix + §6 cross-schema analysis decide scope.

## Outcome: **B — PARTIAL** (one sort token carved by a constitutional constraint)

Most dimensions are feasible and land in this PR. **`bestseller` sort is carved** to a follow-up
(**P-029**) because the only popularity signal lives in `analytics_schema.popular_products`
(migration 0080) and CLAUDE.md §5 **forbids cross-schema JOINs** (only `ref_schema` is exempt) —
honoring it needs a popularity value denormalized into `catalog_schema`, which is its own change.
`cashback_only` is **excluded** (vacuous — every Mopro product earns cashback by the business model).
Everything else (price, brand, rating, free_shipping, in_stock, category-on-search; sort:
recommended/newest/price_asc/price_desc/cashback_desc) ships here.

---

## §1 — Current state (six-layer inventory, read)

| Layer | File | State |
|---|---|---|
| Spec | `api/openapi.yaml:700-734` (`/products`), `:894-948` (`/search`) | `/products`: `category_id,page,per_page,sort`. `/search`: `q,category_id,min_price,max_price,sort,page,per_page` ("with filters"). sort enum `[recommended,newest,price_asc,price_desc,best_selling]`. |
| Client (Go) | `internal/api/gen/` (oapi-codegen) | regenerated from spec |
| Client (Dart) | `mobile/packages/mopro_api/lib/src/api/{catalog,search}_api.dart` | sends spec params |
| **Handler** | `cmd/core-svc/catalog_handlers.go:53-121` | `handleListProducts` reads `category_id/page/per_page/market`; `handleSearch` reads `q/page/per_page/market`. **Both drop sort + all filters.** |
| Service | `internal/catalog/{api.go:30-31,service.go:119-145}` | `ListProductsByCategory(ctx,categoryID,locale,market,page,perPage)`, `SearchSummary(ctx,query,locale,market,page,perPage)` — no filter/sort args |
| Repository | `internal/catalog/repository.go:307-416` | `ListProductsByCategory`/`SearchProductsSummary`: identical SQL; `WHERE category_id/status` (or tsvector); `ORDER BY p.id DESC`; LIMIT/OFFSET. No filter WHERE, no sort switch. |

**Products schema (`catalog_schema.products`, migrations 0010/0061/0065):** `id, seller_id, category_id,
brand TEXT, status, created_at, rating_avg NUMERIC(2,1), rating_count INT`. Variants
(`catalog_schema.variants`): `price_minor, stock, original_price_minor`. The summary SQL sources price
from a `JOIN LATERAL (… ORDER BY price_minor ASC LIMIT 1)` (the **lowest-priced** variant) and joins
`ref_schema.commission_rules` (the allowed cross-schema exception) for `commission_pct_bps`.

---

## §2 — Target state per dimension

| Dim | In spec today | Schema source | SQL clause | Feasible here? |
|---|---|---|---|:--:|
| `category_id` (search) | ✅ /search | `p.category_id` (indexed) | `AND p.category_id = $n` | ✅ |
| `min_price`/`max_price` | ✅ /search | `v.price_minor` (LATERAL lowest) | `AND v.price_minor >= / <= $n` | ✅ |
| `brand` (array) | ❌ | `p.brand TEXT` | `AND p.brand = ANY($arr)` | ✅ (residual scan — index = follow-up) |
| `rating` (min 1–5) | ❌ | `p.rating_avg` (indexed `WHERE rating_count>0`) | `AND p.rating_avg >= $n` | ✅ |
| `free_shipping` (bool) | ❌ | **new column** | `AND p.free_shipping` | ✅ (+migration; data = follow-up) |
| `in_stock` (bool) | ❌ | derived from `variants.stock` | `AND EXISTS(… stock>0)` | ✅ |
| `cashback_only` | ❌ | — | — | ❌ **excluded** (vacuous) |
| **sort** | enum (both) | see §3 | `ORDER BY …` switch | partial (bestseller carved) |

**Price semantic:** filter on the **lowest-variant price** (`v.price_minor` — the value the card
displays), not "any variant in range." Consistent with the displayed price; documented choice.

**Response DTO unchanged:** P-028 is filter *input* only. Exposing `free_shipping` as a card badge is
**P-009** (card merch badges), explicitly out of scope here.

---

## §3 — Sort tokens & PlpSort reconciliation

Frontend `PlpSort` (`plp_filters.dart:7-13`): `recommended, bestseller, newest, price_asc, price_desc,
cashback_desc`. Spec enum today: `recommended, newest, price_asc, price_desc, **best_selling**`.

| Token | ORDER BY | Decision |
|---|---|---|
| `recommended` (default) | `p.id DESC` (current) | ✅ |
| `newest` | `p.created_at DESC` | ✅ |
| `price_asc` | `v.price_minor ASC` | ✅ |
| `price_desc` | `v.price_minor DESC` | ✅ |
| `cashback_desc` | `(v.price_minor * COALESCE(cr.commission_pct_bps,0)) DESC` | ✅ (computable from existing joins) |
| `bestseller` | needs `analytics_schema.popular_products.view_count` | ❌ **carved → P-029** (cross-schema) |

**Decision: spec is canonical, and the spec lists only implemented tokens** —
`[recommended, newest, price_asc, price_desc, cashback_desc]`. Drop `best_selling` (renamed-but-never-honored;
the frontend never sent it — it sends `bestseller`), add `cashback_desc`. The repo's sort switch maps any
unknown/unsupported token (incl. `bestseller`) → `recommended` (**never errors**, mirroring the frontend's
`PlpSort.fromToken` fallback). Keeping `bestseller` out of the spec keeps it honest — exactly the
spec-lies-to-client defect P-028 fixes. P-026's frontend wiring should hide/disable `bestseller` until P-029.

---

## §4 — Schema impact (migration 0081)

Only **one** new column needed:
```sql
ALTER TABLE catalog_schema.products
  ADD COLUMN IF NOT EXISTS free_shipping BOOLEAN NOT NULL DEFAULT FALSE;
```
- Purely additive (DEFAULT FALSE) → migration-safety gate passes; existing rows sane.
- **Data population is a follow-up** (seller onboarding / admin tool): with all rows FALSE, the filter
  returns empty when enabled — correct-but-data-dark, the established P-008b pattern. The filter is *wired*;
  data comes later. (Shipping/cargo is "handled separately per PRD §2.3" — this is just a per-product flag.)
- `rating_avg`, `brand`, `price`, `created_at`, `stock` already exist — no schema work.
- Reversible `.down.sql`: `ALTER TABLE … DROP COLUMN IF EXISTS free_shipping;`

---

## §5 — Performance sanity

| Predicate | Index today | Note |
|---|---|---|
| `category_id` | `products_category_idx(category_id,status)` | ✅ |
| `rating_avg >=` | `products_rating_idx(rating_avg DESC) WHERE rating_count>0` | ✅ |
| `price` range / sort | none on `variants.price_minor` | LATERAL is per-product (cheap); result-set sort acceptable at launch scale |
| `brand = ANY` | none | residual predicate after category/status narrows; **index = follow-up finding** (§1.2 keeps index adds out) |
| `free_shipping` / `in_stock` | none | cheap boolean / EXISTS |

Launch scale (single VDS, modest catalog) makes these acceptable. Index additions are deferred per §1.2;
if `EXPLAIN` shows a hot path post-launch, file a separate index finding.

---

## §6 — Cross-schema constraint (the carve driver)

CLAUDE.md §5: cross-schema SQL JOIN is **FORBIDDEN** except `ref_schema`. The summary SQL already uses
the allowed `ref_schema.commission_rules` join. **rating is safe** — `rating_avg` is denormalized onto
`catalog_schema.products` (maintained by the 0073 reviews write-side), so rating filter/sort need **no**
JOIN. **bestseller is blocked** — popularity is `analytics_schema.popular_products` (0080); a JOIN there
is forbidden. Unblocking it requires denormalizing a popularity counter into `catalog_schema` (event/outbox
sync or a periodic projection) → **P-029 (MED, backend)**.

---

## §7 — Blast radius (signature change)

Threading a `catalog.ProductFilter` struct through the 2 service + 2 repo methods touches:
- Real: `cmd/core-svc/catalog_handlers.go` (2 handlers), `internal/catalog/{service,repository}.go`, `internal/catalog/api.go` (2 interfaces), `internal/catalog/discovery_test.go:40`.
- Mocks (one-token ignored-param add each): `cmd/core-svc/catalog_handlers_test.go`, `internal/cart/service_test.go`, `internal/order/service_test.go`, `internal/e2e/{delivered_multi_seller,order_to_cashback}_test.go`, `internal/catalog/service_test.go` (repo mock).

Mechanical; the cross-module test churn is the honest cost of evolving a shared interface (no new methods —
keeps the interface clean). `ProductFilter{}` zero-value = "no filter," so non-filtering callers are trivial.

---

## §8 — Carves & exclusions

- **Carve → P-029 (MED, backend):** `bestseller` sort. Needs catalog-side popularity (cross-schema ban).
- **Exclude (documented):** `cashback_only` (vacuous). `in_stock` is *included* (cheap EXISTS; the mobile
  `FilterSheet` already has the toggle — a tiny future frontend change to `PlpFilters` lights it up).
- **Secondary (not this PR):** mobile/desktop filter-model divergence + `free_shipping` card badge (P-009)
  + brand/price indexes (perf follow-up).

---

## §9 — Commit plan

```
1 docs       discovery (this doc)
2 spec       openapi.yaml: add brand/rating/free_shipping/in_stock to /products+/search;
             category_id+min_price+max_price to /products; sort enum → implemented set; make api-gen
3 migration  0081_products_free_shipping (additive bool, reversible)
4 domain+repo ProductFilter struct + conditional WHERE/ORDER BY in both summary queries
5 service    thread ProductFilter through ListProductsByCategory + SearchSummary
6 handler    parse + validate the new params; update mocks (blast radius §7)
7 tests      integration: one per dimension + combined + sort + over-filtered + no-filter regression
8 docs       close P-028 (audit RESOLVED-partial), file P-029, unblock P-026; ROADMAP + REPORT
```
(The prompt's 9-slot template collapses: no separate PlpSort commit — folded into spec+repo; Outcome B so
the carve is documented, not built.)

# F-021 — `/products` response ↔ spec reconciliation (discovery)

> The catalog product-summary serializer diverges from its own OpenAPI: it emits
> `cashback_preview.monthly_amount_minor` (spec: `monthly_coin_minor`) plus two
> off-spec extras, and a `meta` pagination envelope (spec: `pagination`). The
> generated clients are spec-correct, so the strict generated parse throws →
> category PLP + search (and the PDP) render empty; the app masks the rest with
> manual mappers. Filed out of F-020. **Outcome A — backend → spec, atomic.**

## Field diff (actual backend vs `api/openapi.yaml`)

| Location | Backend emits | Spec / generated client wants | Verdict |
|---|---|---|---|
| `cashback_preview.monthly_coin_minor` | `monthly_amount_minor` | `monthly_coin_minor` (**required**) | backend wrong → rename |
| `cashback_preview` extras | `reference_rate_bps`, `commission_pct_bps` | (not in `CashbackPreview`) | off-spec, **read nowhere** → drop |
| list envelope | `meta` | `pagination` (required `[data, pagination]`) | backend wrong → rename |

`CashbackPreview` (spec) = `{ monthly_coin_minor (int64, req), currency (req) }`.
`PaginationMeta` (spec) = `{ page, per_page, total, total_pages }` — the backend's
inner object already matches; only the **envelope key** is wrong.

Single backend source: `cmd/core-svc/catalog_handlers.go::cashbackPreviewJSON` +
`buildProductListResponse`. The fin-svc cashback **plan** `monthly_amount_minor`
(`cashback_schema.plans` column, `internal/cashback`, fin OpenAPI) is a **different,
correct** field — explicitly OUT OF SCOPE.

**The spec is canonical** (confirmed): the generated **Dart** `ProductSummary` /
`CashbackPreview` and the **web** `web/types/api.ts` both already use
`monthly_coin_minor` + `pagination`; client code reads `.pagination`; the manual
mappers' own doc-comments call the backend the drifting side. So `api/openapi.yaml`
is **not** edited and **no client regen is needed** — the clients already match.

## Every `/products` / `ProductSummary` consumer

Backend endpoints emitting the shared `buildProductSummaryJSON` / `cashbackPreviewJSON`
shape (all fixed by the two serializer edits): `GET /products`, `GET /search`,
`GET /sellers/{slug}/products` (all via `buildProductListResponse`),
`GET /home/flash-deals`, `GET /recommendations/home`, `GET /me/recently-viewed`,
`GET /products/{id}/similar`, and `GET /products/{id}` (PDP, same `cashbackPreviewJSON`).

| Mobile consumer | Endpoint | Parse path today | Status today | After fix |
|---|---|---|---|---|
| `products_by_category_provider` (PLP) | `/products?category_id` | **generated** `api.listProducts` | **EMPTY (throws)** | works, no code change |
| `filtered_products_provider` | `/products` | **generated** `api.listProducts` | **EMPTY (throws)** | works, no code change |
| `product_detail_provider` (PDP) | `/products/{id}` | **generated** `api.getProduct` | **broken cashback** | works, no code change |
| `products_rail_provider` (Home rails) | `/products?sort` | manual `productSummaryFromApi` (F-020 workaround) | works | → generated `api.listProducts` |
| `home_recommendations_provider` | `/recommendations/home` | manual `productSummaryFromApi` | works | → `ProductSummary.fromJson` |
| `recently_viewed_provider` | `/me/recently-viewed` | manual `productSummaryFromApi` | works | → `ProductSummary.fromJson` |
| `similar_products_provider` | `/products/{id}/similar` | manual `productSummaryFromApi` | works | → `ProductSummary.fromJson` |
| `seller_storefront_repository` | `/sellers/{slug}/products` | manual `sellerProductFromApi` | works | → `ProductSummary.fromJson` |

Manual mappers (both read `monthly_amount_minor`, retired after the fix):
- `mobile/lib/features/catalog/data/product_summary_api.dart` —
  `productSummaryFromApi` (+ `productSummaryStatusFromApi`, used only here). 4 call-sites.
- `mobile/lib/features/seller/data/seller_storefront_repository.dart` —
  `sellerProductFromApi`. 1 call-site.

The non-generated endpoints (recommendations / recently-viewed / similar / storefront)
have no `api.*` method, so their consumers keep raw-dio fetch but parse the now
spec-shaped map with the generated `ProductSummary.fromJson` — the "generated parse
path" the mission means. PLP/filtered/PDP already use generated `api.*` and need
**zero** code change once the backend is spec-correct.

## Decision — Outcome A (atomic)

Blast radius is small and coherent: **2 backend serializer edits**, **0 spec/regen**,
**~6 mobile call-site swaps + 2 mapper deletions**, **1 regression test**. No
transitional both-shapes needed (Outcome B), no spec correction (Outcome C). Web is
already spec-shaped, so the change *fixes* web too; nothing reads the dropped extras.

## Plan (one commit per concern)

1. This doc.
2. **Backend serializer → spec** (`cmd/core-svc/catalog_handlers.go`):
   `cashbackPreviewJSON` `monthly_amount_minor`→`monthly_coin_minor`, drop
   `reference_rate_bps` + `commission_pct_bps` (2 construction sites); envelope
   `meta`→`pagination`. NULL-safe; no value/logic change. **+ regression test**
   (`cmd/core-svc`): marshal `buildProductSummaryJSON` + `buildProductListResponse`,
   assert the spec keys (`cashback_preview.monthly_coin_minor` present /
   `monthly_amount_minor` absent; `pagination` present / `meta` absent) so the
   serializer can't silently drift again (systemic root of F-020 + F-021).
3. **Mobile — migrate consumers + retire mappers**: swap the 5 mapper call-sites to
   `ProductSummary.fromJson`; revert `products_rail_provider` to generated
   `api.listProducts` (F-020 workaround no longer needed; the F-020 **handler**
   global-list fix stays); delete `product_summary_api.dart` +
   `sellerProductFromApi`.
4. **Local verify** (`scripts/dev/local-phaseb.sh` + emulator): category PLP, search,
   PDP, **and** all rails / recommendations / flash-deals / storefront render — none
   empty, none regressed.

No `api/openapi.yaml` change; no Go/Dart client regen (spec already correct).

# ProductSummary Enrichment — Discovery & per-field decision

Backend foundation for the data-dark card/PDP findings (P-004, P-009, P-008b).
Per-field outcome A (catalog has it) / B (denormalize) / C (cross-schema block → file).
Branch `feat/productsummary-enrich`.

## Headline: the codebase evolved since the PR #77 audit — most of this is already done.

`discount_pct` is **already emitted**; `original_price_minor` + `flash_price_minor` are already on
`ProductSummary`; `user_favorites` turns out to live in **catalog_schema** (no cross-schema problem).
So the actual delta is **2 small Outcome-A fields** + **1 deferred Outcome-C compliance finding**.

## §1 — Current ProductSummary (re-read)

- Spec (`api/openapi.yaml:2347`): `id, seller_id, category_id, brand, status, title, price_minor,
  price_currency, cover_image_url, commission_pct_bps, original_price_minor, **discount_pct**,
  rating_avg, rating_count, **flash_price_minor**, cashback_preview`.
- Go `ProductSummaryRow` (`internal/catalog/domain.go:105`): mirrors the above minus the computed bits.
- Handler `buildProductSummaryJSON` (`cmd/core-svc/catalog_handlers.go:303`) **computes + emits `discount_pct`**
  from `original_price_minor`/`price_minor`. Shared by the list + flash-deals responses.
- Producers of `ProductSummaryRow`: the shared `productSummarySelect` const + `scanProductSummaries`
  (`ListProductsByCategory` + `SearchProductsSummary`) and `ListProductsByIDs` (own query/scan; also the
  flash-deals card hydration path).

## §2 — Per-field decision matrix

| Field | Schema location | Outcome | Strategy |
|---|---|---|---|
| **discount_pct** | computed from `original_price_minor` (variants, 0065) | **ALREADY DONE** | `buildProductSummaryJSON:307-313` already computes + emits it. No work. P-008b discount portion ✅. |
| **favorites_count** | `catalog_schema.user_favorites` (migration 0064 — **same schema**) | **A** | correlated subquery `(SELECT count(*) FROM catalog_schema.user_favorites uf WHERE uf.product_id = p.id)` in the summary SELECTs. No cross-schema JOIN (it's a same-schema subquery); no event listener. + a `product_id` index (0064 only indexes `user_id`). |
| **free_shipping** (the P-009 badge piece) | `catalog_schema.products.free_shipping` (0081, P-028) | **A** | passthrough `p.free_shipping` → `ProductSummary`. The other P-009 badges are already derivable client-side: discount → `discount_pct`; flash → `flash_price_minor != null`. (Bestseller badge = P-029, out of scope.) |
| **structured badge system** | — | **NOT-BUILT** (§2.3 Outcome C) | no campaign/badge *system* exists to surface; building one is a feature, not enrichment (anti-goal). The actionable data is the three derivable signals above — no `badges[]` array introduced. |
| **lowest_30d_price** | **no price-history table exists** | **C → P-030** | needs a new `price_history` table + a snapshot/tracking mechanism + a cron-placement decision (which binary owns it). >500 LOC + new infra (anti-goal §9). Compliance-serious (TR consumer-protection + EU) → deserves a dedicated, careful PR, not a bundled rush. Filed as **P-030 (HIGH, backend/compliance)**. |

## §3 — What ships here (Outcome A only)

1. **Migration** (additive): `user_fav_product_idx ON catalog_schema.user_favorites(product_id)` — the
   count subquery's index (the only thing the enrichment *inherently* needs; 0064 indexes `user_id` only).
2. **Domain + repo + handler** (one atomic Go commit — scan must match the SELECT):
   - `ProductSummaryRow` gains `FavoritesCount int` + `FreeShipping bool`.
   - `productSummarySelect` + `scanProductSummaries` + `ListProductsByIDs` (query + scan) add the two columns.
   - `productSummaryJSON` gains `favorites_count` + `free_shipping`; `buildProductSummaryJSON` maps them.
3. **Spec + regen** both clients; `flutter analyze` post-regen (PR #85 fake-blast-radius watch).
4. **Integration test**: favorites_count counts `user_favorites` rows; free_shipping passes through.

## §4 — No Outcome-B work (and why that's good news)

The prompt anticipated favorites_count needing an outbox-driven denormalized counter (Outcome B). Discovery
shows `user_favorites` is in **catalog_schema**, so a same-schema subquery suffices (Outcome A) — **no event
listener, no new sync mechanism, no eventual-consistency window, no reconciliation job.** This sidesteps the
§9 anti-goal entirely. (If `user_favorites` ever moves to its own schema/service, this would flip to B.)

## §5 — Mobile fake-blast-radius (PR #85 lesson)

Adding fields to the `ProductSummary` *model* changes the generated Dart constructor. Make both fields
defaulted (`favorites_count: integer default 0`, `free_shipping: boolean default false`) and run
`flutter analyze` locally after `make api-gen`; fix any `invalid_override`/missing-arg breaks in test fakes
before pushing (don't burn a CI round-trip).

## §6 — Findings filed
- **P-030 (HIGH, backend/compliance)** — `lowest_30d_price` needs price-history infrastructure. Unblocks the
  P-008b "lowest in 30 days" copy (a TR/EU consumer-protection requirement). Architectural prerequisites:
  a `price_history` table, a snapshot mechanism (on-price-change hook or periodic snapshot), and the
  cron-placement decision. Out of this PR's scope.

## §7 — Frontend follow-up (after this lands)
P-004 (favorites_count on card/PDP) + P-009 (free-shipping / discount / flash badges from the now-exposed
fields) become a small frontend-wiring PR (~100-200 LOC), same shape as P-026's wiring.

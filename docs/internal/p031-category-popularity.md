# P-031 category-scoped popularity — discovery (Outcome C: deferred)

> Carve from P-029 (#90): a category PLP's `bestseller` sort uses **global** popularity (a reasonable
> proxy) because `popular_products` only populates the `'global'` scope. This PR set out to add
> category-scoped popularity. **Discovery → Outcome C (deferred):** the analytics source can't carry a
> category dimension without a forbidden cross-schema JOIN or out-of-scope event enrichment. Paths are
> `internal/analytics/` (the prompt's `services/core-svc/...` is wrong); the global proxy is retained.

## 1. The schema is already category-ready — but the data isn't

`analytics_schema.popular_products` (migration 0080) is keyed `(scope, product_id)` with
`scope TEXT` documented as `'global' | 'category:{categoryId}'` and an index on `(scope, view_count DESC)`.
So **no migration is needed** — the category tier was designed in. But `RebuildPopular`
(`internal/analytics/repository.go`) only ever inserts `'global'` rows, and `PopularProductIDs(ctx, limit)`
only reads `scope = 'global'`. The codebase says so explicitly (repository.go):

> *"Per-category scope is deliberately [deferred] … the `scope` column is retained for a future category
> tier once categoryId is carried on the product_view payload (Backlog)."*

## 2. Why category scope can't be built here (the §5 wall)

`RebuildPopular` aggregates from `analytics_schema.analytics_events`:
```sql
INSERT INTO popular_products (scope, product_id, view_count)
SELECT 'global', (payload->>'productId')::bigint, COUNT(*)
  FROM analytics_schema.analytics_events
 WHERE event_type = 'product_view' AND payload ? 'productId' …
 GROUP BY (payload->>'productId')::bigint
```

True per-category popularity is `GROUP BY (category, product)` over `product_view` events — which needs a
**category per view**. Discovery confirms there is none:

- `product_view` payload carries **only `productId`** (`domain.go: requiredPayloadFields[EventProductView]
  = {"productId"}`). The separate `category_view` event carries `categoryId` but **no** `productId`, so
  the two can't be joined per product.
- `analytics_schema` has **no** `category_id` column and **no** product→category projection anywhere
  (`analytics_events`, `recently_viewed`, `popular_products` — none).
- The only place category lives is `catalog_schema.products` — and **CLAUDE.md §5 forbids the
  cross-schema JOIN** (`analytics_schema` ⋈ `catalog_schema`), the one thing that would let the
  aggregation derive category.

So this is **Outcome C** (source events lack category info), exactly the prompt's blocked case.

## 3. Alternatives considered (and rejected)

| Approach | Verdict |
|---|---|
| JOIN `product_view` events → `catalog_schema.products` for category | ❌ **§5 violation** (cross-schema JOIN; analytics is a separate schema). |
| Enrich the event at **ingest** (look up category via `catalog.Service` per `product_view`) | ❌ Architectural: adds a catalog read to the ingest hot path + couples analytics ingest to catalog; only fixes future events (history still needs the JOIN). Out of scope (§8 "don't refactor analytics architecture"). |
| Carry `categoryId` on the `product_view` **payload** (client sends it) | ✅ **the codebase's documented intended path** — but it's a **frontend** change (out of scope §1.2) + only enriches future events. → filed as **P-033**. |
| Session-correlate `category_view` → subsequent `product_view` to attribute a category | ❌ A heuristic (imperfect attribution), new windowing aggregation, and diverges from the documented payload-based design. |
| In-process: bucket the *globally-popular* products by their catalog category | ❌ Degraded — ranks only globally-popular products by category, not true per-category popularity (a category's local #1 that isn't globally popular never surfaces). |

## 4. Decision — discovery-only; global proxy retained

No code change. `bestseller` on a category PLP continues to use **global** popularity (PR #90's reasonable
proxy — globally-popular products in a category are usually category-popular too; the imperfection is a
niche-category leader that isn't globally popular ranking lower). The category tier stays schema-ready and
unbuilt, as the authors intended.

**Filed P-033** (the enabler): carry `categoryId` on the `product_view` payload (client emit +
`requiredPayloadFields` + validation), after which `RebuildPopular` can populate `'category:{id}'` rows
(pure same-schema `GROUP BY categoryId, productId`) and `PopularProductIDs` can take a scope — **then**
P-031 is a small, mechanical follow-up with no §5 issue.

## 5. Out of scope

Frontend; the event-payload enrichment itself (P-033); per-brand/seller scopes; the chi-square flake;
P-007; PDP-strikethrough. No migration, no schema change, no new analytics dimension built here.

## 6. Commit plan

1. this doc.
2. docs closure — audit (P-031 → DEFERRED, root-caused; file **P-033** enabler), ROADMAP, REPORT.

# P-029 Bestseller Sort — Architecture & Discovery

Make `bestseller` sort by real popularity instead of falling back to `recommended`
(P-028's graceful map). Branch `feat/bestseller-sort`.

## Decision: **Pattern B (in-process read), handler-orchestrated, global scope**

The prompt's default (Pattern A — denormalize via outbox) assumes a *service boundary* where
denormalization avoids cross-service calls. **It doesn't apply here:** analytics is an **in-process
core-svc module** (`internal/analytics/`), and `analytics.Service.PopularProductIDs(ctx, limit)` is
**already wired into core-svc** + already used by sibling handlers (`handleHomeRecommendations`,
`handleSimilarProducts`, `handleRecentlyViewed` — main.go:488/493/758). So the catalog handler can read
the global popularity ranking in-process — **no schema change, no sync mechanism, no new infra** (the
cross-binary sync Pattern A would need is the *wrong* trade here). No cross-schema JOIN (CLAUDE.md §5):
the handler does two separate reads (analytics.Service for IDs, catalog repo for products) and combines
them — never a SQL JOIN across schemas.

## Discovery facts

- `analytics_schema.popular_products` (migration 0080): `(scope, product_id, view_count, refreshed_at)`,
  per-scope (`'global'` | `'category:{id}'`), **daily truncate+rebuild** (jobs-svc 05:00 cron →
  `analytics.Service.RefreshRecommendations`). Derived, never source-of-truth. `product_id` is a BIGINT
  **soft ref** (no cross-schema FK — the §5 pattern).
- **Only the `'global'` scope is populated.** `Repository.RebuildPopular` (`api.go:98-100`) "recomputes
  'global' scope" — category scopes are schema-supported but **not built**. Extending the computation to
  category scopes is **out of scope** (anti-goal §1.2 — don't modify analytics's computation). So
  bestseller is **global-scope only** this PR; category-scoped bestseller is a follow-up (**P-031**, below).
- `analytics.Service.PopularProductIDs(ctx, limit) → []int64` (api.go:49) reads
  `popular_products WHERE scope='global' ORDER BY view_count DESC` (repository.go:310). The ready primitive.
- `bestseller` is currently hidden from the frontend sort selectors (PR #86) but kept in `PlpSort` +
  deep-linkable; P-028 dropped it from the spec `sort` enum + maps unknown→recommended.

## Design

1. **`catalog.ProductFilter` gets `PopularIDs []int64`** — handler-provided ordering seed for bestseller.
2. **Repo** (`ListProductsByCategory` + `SearchProductsSummary`): when `len(filter.PopularIDs) > 0`, the
   ORDER BY becomes `array_position($ids::bigint[], p.id) NULLS LAST, p.id DESC` — **all products, the
   globally-popular ones first (in popularity order), the rest after** (no `WHERE id = ANY` restriction →
   **no empty PLPs**). Otherwise the existing `orderByClause(sort)` is used.
3. **Handlers** (`handleListProducts` + `handleSearch`): gain an `analytics.Service` param (the established
   sibling-handler shape); when `sort == "bestseller"`, fetch `PopularProductIDs(ctx, bestsellerCap=200)`
   and set `filter.PopularIDs`. On error/empty → `PopularIDs` stays empty → `orderByClause("bestseller")`
   → `recommended` (graceful degradation; no breakage before the first analytics refresh).
4. **main.go**: thread `analyticsSvc` into the two catalog handlers (already constructed at main.go:173).
5. **Spec**: re-add `bestseller` to the `sort` enum (it's a real sort again); regen clients.

`catalog.Service`/`Repository` interfaces are **unchanged** (the filter already flows through); catalog
stays decoupled from analytics — the *handler* orchestrates (correct layer, per the sibling handlers).

## Semantics + limitations (documented)
- **Global popularity**, applied on every surface. On a category PLP, bestseller = the category's products
  with the globally-popular ones first — a reasonable proxy; true category-scoped bestseller needs the
  analytics category-scope computation (**P-031**, MED, analytics-side follow-up).
- **Eventual consistency**: popularity is a daily projection — fine for a sort (no urgency).
- **Perf**: `array_position` is O(K) per row (K=200 cap); acceptable at launch scale. If a huge category
  shows latency, Pattern A (an indexed `popularity_rank` column synced from the global ranking) is the
  optimization — noted, not needed now.

## Commit plan
1. discovery (this doc)
2. impl: `ProductFilter.PopularIDs` + repo array_position ordering + handler bestseller fetch + main.go wiring + integration test
3. spec: re-add `bestseller` to the sort enum + regen clients
4. docs closure (P-029 RESOLVED Pattern B; file P-031 for category-scope; ROADMAP + REPORT)

## Follow-ups filed
- **P-031** (MED, analytics + backend): populate category-scoped popularity (`RebuildPopular` per
  `category:{id}`) + a scoped `PopularProductIDs(scope, limit)`, so category-PLP bestseller is
  category-specific rather than global.
- **Frontend** (small): un-hide `bestseller` in the sort selectors + its i18n label (deep-linkable already).

# P-031 per-category bestseller aggregation — discovery (Outcome A, all components)

> Completes the chain: PR #90 (global bestseller) → PR #95 (deferred P-031, Outcome C) → PR #99/P-033
> (`product_view` now carries `categoryId`) → **this PR** (per-category aggregation + scoped read + handler
> routing). **Stacked on `feat/event-categoryid` (#99)** — P-031 depends on P-033's category-carrying
> events and edits the same docs/`analytics_test.go`; retargets to main when #99 merges. No migration
> (`popular_products.scope` is already category-ready), no frontend (PR #86 un-hid the sort), no event change.

## 1. The three sites (Outcome A across all)

| Layer | Today | Change |
|---|---|---|
| `Repository` | `PopularGlobalIDs(ctx,limit)` → `scope='global'` | **add** `PopularCategoryIDs(ctx,categoryID,limit)` → `scope='category:<id>'` (mirror) |
| `Service` | `PopularProductIDs(ctx,limit)` → global (3 callers: bestseller + 2 recs-fallback) | **add sibling** `PopularProductIDsInCategory(ctx,categoryID,limit)` — keeps the global signature stable (additive interface method) |
| Handler | `applyBestsellerOrder` always calls global | route by `filter.CategoryID` (see §3) |
| `RebuildPopular` | one global pass | **add** a per-category pass in the same tx |

Additive interface methods break Go fakes: `fakeRepo` (`analytics_test.go`) gains a `PopularCategoryIDs`
stub; `fakeRecsSvc` (`recommendations_handlers_test.go`) gains a `PopularProductIDsInCategory` stub.

## 2. RebuildPopular per-category pass

After the existing global INSERT (unchanged), in the **same tx** (one `TRUNCATE` clears global+category, then
both passes repopulate), add a **top-N-per-category** pass — bounded like the global `LIMIT` via a window:

```sql
INSERT INTO analytics_schema.popular_products (scope, product_id, view_count)
SELECT 'category:' || cat::text, pid, cnt
FROM (
  SELECT (payload->>'categoryId')::numeric::bigint AS cat,
         (payload->>'productId')::numeric::bigint  AS pid,
         COUNT(*) AS cnt,
         ROW_NUMBER() OVER (PARTITION BY (payload->>'categoryId')::numeric::bigint
                            ORDER BY COUNT(*) DESC, (payload->>'productId')::numeric::bigint) AS rn
  FROM analytics_schema.analytics_events
  WHERE event_type='product_view' AND server_ts >= $1
    AND payload ? 'productId' AND payload ? 'categoryId'
  GROUP BY (payload->>'categoryId')::numeric::bigint, (payload->>'productId')::numeric::bigint
) ranked WHERE rn <= $2;
```
- **Same time window, same score** (`COUNT(*)`), same `limit` ($2 = top-N **per category**). No change to the
  global pass. `'category:'||cat::text` matches the read's `fmt.Sprintf("category:%d", id)`.
- **Volume:** ≤ `limit` rows × #categories-with-views. The `(scope, view_count DESC)` index serves the read.
- **Idempotent:** the single `TRUNCATE` + re-INSERT preserves the existing replace semantic.

## 3. Handler routing — category-scope with a global FALLBACK (avoids a regression)

`applyBestsellerOrder` (bestseller sort only):
- `filter.CategoryID == nil` (e.g. search bestseller) → **global** (unchanged).
- `filter.CategoryID != nil` (category PLP) → **category-scoped**; **if it returns empty, fall back to
  global**, then the repo's existing `array_position … NULLS LAST` falls back to `recommended` if both empty.

**Why the global fallback is required, not optional:** per P-033's additive decision, per-category data
accrues only from *new* events, so most categories are empty until enough events land. The *current*
behavior (PR #90/#95) for a category PLP bestseller is the **global proxy**. Without the fallback, P-031
would change empty-category bestseller from "global proxy" → "recommended" — a **regression**. The fallback
keeps the proxy for empty categories and uses true category popularity once it exists.

## 4. Edge cases (§2.5)

- Events without `categoryId` (historical / web / old app builds) → excluded from the per-category pass
  (the `payload ? 'categoryId'` guard), still counted in global. Both correct.
- A product viewed in several categories in-window → contributes to each category's count + global. Correct.
- Tiny category → noisy top-N (not a defect); empty category → global fallback (§3).
- Category filter **without** bestseller sort → `applyBestsellerOrder` returns early; `PopularProductIDs*`
  not called. Orthogonal, unchanged.

## 5. Out of scope

Event payload (P-033 ✅); other scopes (brand/seller); migration (scope column exists); frontend (#86);
score formula / time window; backfilling historical per-category (impossible — additive Outcome A).
chi-square flake, PDP-strikethrough — untouched. CLAUDE.md §5 honored (per-category is a pure
same-schema `analytics_schema` GROUP BY — no catalog JOIN).

## 6. Commit plan

1. this doc.
2. `Repository.PopularCategoryIDs` (iface+impl+`fakeRepo` stub) + `RebuildPopular` per-category pass.
3. `Service.PopularProductIDsInCategory` (iface+impl+`fakeRecsSvc` stub).
4. handler routing (category-scope + global fallback).
5. tests — integration (per-category aggregation + scoped read + cross-category isolation) + handler routing unit (global / category / empty-fallback / orthogonal).
6. docs closure — audit P-031 RESOLVED (chain complete) + "all parity findings closed end-to-end"; ROADMAP; REPORT.

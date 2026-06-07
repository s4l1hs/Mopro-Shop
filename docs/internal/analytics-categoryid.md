# A-CAT — categoryId Backfill Terminal Status (decision doc)

> Drives the additive-Outcome-A consideration from PR #99 to a terminal status. **Decision-first**:
> the deliverable is the decision, not a backfill. Source-verified 2026-06-07.

## Terminal status: **NOT-ACTIONABLE** (graceful-degrade is by design and adequate)

Three independent grounds, any one sufficient; together decisive.

## 1. The mechanism (what #99/#100 actually built)

- **#99 (P-033)** carries `categoryId` on the `product_view` payload at emit time (mobile PDP holds
  the loaded `Product.categoryId`). JSONB, optional forever; old/offline/web clients omit it.
- **#100 (P-031)** `RebuildPopular` does a **same-schema** per-category pass:
  `GROUP BY (payload->>'categoryId'), (payload->>'productId')` over `analytics_schema.analytics_events`,
  writing `scope='category:<id>'` rows. Events lacking `categoryId` are excluded from the category
  pass but **still counted in the global pass** (`repository.go:235`).
- **Consumer** (`cmd/core-svc/catalog_handlers.go:79`): `bestseller` + `category_id` →
  `PopularProductIDsInCategory`; **on empty, falls back to `PopularProductIDs` (global proxy)**;
  never regresses to `recommended`. The degrade is an explicit, tested branch.

## 2. Ground A — the popularity window is trailing-30d, so the gap is SELF-HEALING

`RebuildPopular` counts only `server_ts >= now() - 30d` (`service.go:156`, `popularLookbackDays=30`).
Therefore every event that lacks `categoryId` **ages out of the ranking window within 30 days** of the
categoryId-emitting client (#99) going live. After that rolling month, the per-category tier is built
**entirely** from natural categoryId-carrying traffic — with **no backfill**. A backfill's entire value
lifetime is ≤30 days and is then overwritten by real data. Spending engineering on a ≤30-day-lived
artifact that self-replaces is net-negative.

## 3. Ground B — there is currently NOTHING to backfill (live-verified)

Production runs the 2026-05-26 build (pre-analytics-migration; see the deploy-health arc). Live check
2026-06-07: **`analytics_schema.analytics_events` does not exist on prod** (`to_regclass` → NULL). Zero
events, zero of them missing `categoryId`. The "historical events lack categoryId" premise has an empty
referent today. By the time analytics is deployed AND accrues a 30-day history, the #99 client will be
emitting `categoryId` for that same window (Ground A) — the worst-case historical gap is the deploy-to-
first-categoryId-event lag, which is days, not a backlog.

## 4. Ground C — no live category is harmed

The fallback returns the **global** most-viewed products — a coherent bestseller list, just not
category-specialised — for any category without its own history yet. Each category self-populates
independently as its `product_view` events accrue (Ground A). There is no permanent degradation, no
empty list, no error surfaced to the user. "Harm" would require a category that (a) has heavy traffic,
(b) within the 30-day window, (c) entirely pre-#99 — impossible once #99's client is the live client.

## 5. The §5-safe path, for the record (NOT taken)

Had a backfill been warranted, it would be feasible without violating CLAUDE.md §5 (no cross-schema
JOIN): `analytics` and `catalog` are **both in-process in core-svc** (`cmd/core-svc/main.go`), so a job
could `SELECT DISTINCT (payload->>'productId')` from category-less events → call a catalog
**Service** method (e.g. `CategoriesForProducts([]id) map[id]id`, which does not exist today and would
itself need adding) → `UPDATE analytics_events SET payload = payload || jsonb_build_object('categoryId',…)`
in idempotent batches. This is an **in-process service call + same-schema UPDATE**, never a JOIN across
`catalog_schema`/`analytics_schema`. Documented so a future FIX (if Ground A/B/C ever cease to hold —
e.g. a switch to a long lookback window) has the boundary-safe blueprint ready. Not built here:
Grounds A–C make it unwarranted, and §7-4 forbids building a backfill by default.

## 6. Going-forward correctness (unchanged, confirmed)

The #99 pipeline is correct and untouched: new `product_view` events carry `categoryId`; `RebuildPopular`
consumes it same-schema; the handler degrades gracefully until each category accrues. Nothing in this PR
changes the pipeline, the ranking math (#100), or the catalog schema.

## 7. Decision

**NOT-ACTIONABLE — closed.** No migration, no backfill job, no code change. The global-proxy degrade is
the intended, sufficient steady state; the gap self-heals on a 30-day rolling window; prod has zero
historical events to backfill. Re-open only if the popularity lookback window is materially lengthened
**and** a high-traffic category demonstrably needs pre-window ranking — at which point §5 gives the
in-process-service-call blueprint above (and a `catalog.CategoriesForProducts` Service method to add).

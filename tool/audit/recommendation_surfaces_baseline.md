# Audit — Recommendation Surfaces (closing the Tranche 4 analytics loop)

Read-only baseline. file:line + observation.

## Branch-point (§1.1)
- PR #34 (photo upload) merged into `feat/seller-facing-and-platform-growth`
  (tip `2c71e77a`, has migration 0079). Accumulation branch holds
  5a+slug+5b+dashboard+photo; **not on main** (main `3234ac92`). Branched
  `feat/recommendation-surfaces` off it. `make verify` green → no hygiene commit.

## §2.2 Existing recommendation surface
- `GET /recommendations` is a **200-empty stub** (`catalog_handlers.go:218`
  `handleListRecommendations` → `{data: []}`; wired `main.go:469`). Not 501.
- PDP "related" rail EXISTS: `product_detail_screen.dart:389/778` —
  `ProductRail(title: 'product.related_title'.tr(), sort: 'recommended')` backed
  by `productsRailProvider('recommended')` (a generic sort-key rail, NOT co-view,
  NOT the stub). §6 rewires its data source to `similarProductsProvider(id)`.
- No `popular_products` / co-view / `view_count` table exists yet.

## §2.3 Analytics substrate (PR #27/#29)
- `analytics_schema.analytics_events` (migration 0075): `session_id`, `user_id`
  (nullable/guest), `event_type`, `payload` JSONB, `client_ts`, `server_ts`,
  `ingest_batch_id`. Index `(session_id, server_ts)`. `EventProductView =
  "product_view"` with `payload.productId`. Ideal for popularity (count
  product_view in 30d) + co-view (group by session within a window).
- `analytics_schema.user_recently_viewed` projection + `analytics.Service`
  (ingest/consent/read in core-svc; prune/rebuild crons in jobs-svc).
- **Read→hydrate pattern (mirror this):** `handleRecentlyViewed(analyticsSvc,
  catalogSvc, …)` — analytics returns IDs, `catalogSvc.ListProductsByIDs` enriches
  to ProductSummary, order preserved. No cross-schema JOIN.

## §2.4 Refresh-job infra
- `internal/analytics/cron.go` (robfig/cron/v3): retention prune 03:00 +
  recently-viewed rebuild 04:00, wired into `cmd/jobs-svc/main.go:108`. New
  recommendation refresh = a **05:00** entry here. `analytics.Service` gains
  `RefreshPopular` / `RefreshCoViews`.

## §2.5 Rails
- `ProductListRail` (list-driven, PR #29) + `ProductRail` (sort-key-driven) both
  present. Home recommendation rail → `ProductListRail` (mirrors the
  recently-viewed rail). PDP "Benzer ürünler" → swap `ProductRail('recommended')`
  for a `ProductListRail` fed by `similarProductsProvider`.

## Schema placement decision
Projections (`popular_products`, `product_co_views`) are derived from
`analytics_events` → live in **`analytics_schema`** (owned by the analytics
module; the refresh reads events same-schema, no cross-schema read). `product_id`
is a **plain BIGINT soft reference** to catalog_schema.products — NO cross-schema
FK (CLAUDE.md §5 / CONTRIBUTING). The prompt's `REFERENCES products(id)` is
adapted to a soft ref since recommendations ≠ catalog schema. Endpoints
(core-svc) call `analytics.Service` for ranked IDs → hydrate via
`catalog.ListProductsByIDs` (same pattern as recently-viewed). No new module.

## §2.1 Algorithm decision — AskUserQuestion (data-volume reality)
**Data volume today:** dev/seed `analytics_events` has ~no real `product_view`
traffic (no production usage), so co-view will be **empty/sparse until prod
accumulates**. The popularity + co-view tables self-populate via the daily
refresh; the §3.3 fallback (co-view → category-popular → global-popular) covers
cold-start. Options A (popularity only) / B (co-view) / C (hybrid: popularity
home + co-view PDP) surfaced to the owner. §1.6 #1 (co-view sparse) noted.

## Baselines (§1.3)
- `go test ./...` green; `flutter analyze` clean; `flutter build web` ~4.56 MB;
  parity ~60%. Analytics contracts (PR #27): `analytics_events` schema +
  `analytics.Service` read/cron surface = the inputs this PR consumes.

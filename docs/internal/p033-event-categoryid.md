# P-033 carry categoryId on product_view — discovery (Outcome A: additive)

> Unblocks P-031. The chain: PR #90 wired `bestseller` via global `PopularProductIDs`; PR #95 deferred
> per-category popularity (P-031) as Outcome C because `RebuildPopular`'s source `product_view` events
> carry only `productId` and §5 forbids the catalog JOIN. The fix is to carry `categoryId` on the event
> **at emit time** (the PDP already has it). Paths are `internal/analytics/` + `mobile/lib/` (the prompt's
> `services/` / web-emit assumptions are corrected below).

## 1. Backend already accepts it (additive) — almost nothing to change

`internal/analytics/domain.go`:
- Events are `AnalyticsEvent{Type string; Payload map[string]any}`; the payload is stored as **JSONB** in
  `analytics_schema.analytics_events` (0075). So a new key needs **no migration**.
- `ValidateBatch` checks only that each event's **required** fields are present
  (`requiredPayloadFields[EventProductView] = {"productId"}`) and **does not reject extra keys**, and does
  **not** value-validate any field ("presence, not value — §3.3"). So a `product_view` payload with
  `categoryId` is **already accepted today** and flows into the JSONB untouched.
- The ingest endpoint is **hand-written** (not in `api/openapi.yaml`) — no codegen, no client regen.

→ **Outcome A (additive).** `categoryId` stays **optional** (not added to `requiredPayloadFields`):
deployed app versions emit only `productId`, and offline/historical events never will — requiring it
would reject in-flight events. Backend change = a documenting comment + a contract test pinning the
additive behaviour (so nobody later adds strict-key rejection). **No value-validation** is added — that
would break the codebase's presence-only convention for a single field; `RebuildPopular` (P-031) will
parse `(payload->>'categoryId')::numeric::bigint` defensively, exactly as it already does for `productId`.

## 2. Emit sites

**Mobile — one site.** `mobile/lib/features/catalog/screens/product_detail_screen.dart` (initState,
post-frame): `track(AnalyticsEvent('product_view', {'productId': widget.product.id}))`. The PDP holds the
loaded `Product`, and the generated `Product` model carries `categoryId` (`product.dart:108`, required
`int`) — so `categoryId` is **always in scope** at the emit. Add it: `{'productId': …, 'categoryId':
widget.product.categoryId}`.

**Edge cases (§2.6) — all resolved by construction.** The event fires on **PDP mount with the loaded
product**, so it always carries the **product's own category** regardless of how the PDP was reached
(deep-link, search result, recommended carousel). That is exactly the category P-031 wants to count — no
`null` case, no source-surface ambiguity.

**Web — now the Flutter build (ADR-0005).** The standalone Next.js `web/` app was removed; the web
storefront is the same Flutter app as mobile (`flutter build web`), so it emits `product_view` through the
**same** analytics path as mobile — no separate web emission to reconcile. (Historically the Next.js `web/`
emitted nothing to the in-house pipeline; that gap is moot now that web and mobile share one client.) For
P-033 there is nothing web-specific to change (P-031 needs the shared client stream + future
clients, and web traffic simply won't contribute per-category counts until web analytics exists).

## 3. Consumer impact

`RebuildPopular` is **not** changed here (that is P-031). It currently only reads `productId` for the
`'global'` scope; the new `categoryId` key rides along in the JSONB, ready for P-031's same-schema
`GROUP BY (payload->>'categoryId'), (payload->>'productId')`. No other consumer reads `product_view`
payload fields rigidly.

## 4. Decision + rollout

- **Outcome A additive**, `categoryId` optional **forever** (old/offline clients + web justify it).
- No migration (JSONB), no spec/regen (hand-written ingest), no value-validation (presence-only convention).
- After this lands, **P-031 is unblocked** — a small same-schema follow-up.

## 5. Out of scope

P-031's aggregation; `PopularProductIDs` scope param; other event dimensions (brand/seller); web analytics
integration; event-bus/batching changes; backfilling historical events (impossible). chi-square flake,
PDP-strikethrough — untouched.

## 6. Commit plan

1. this doc.
2. backend: document `categoryId` as an accepted optional `product_view` field + a Go contract test (accepts with/without; payload preserved).
3. mobile: emit `categoryId` on `product_view` + a focused PDP emit test (capturing `AnalyticsService`).
4. docs closure — audit (P-033 RESOLVED Outcome A; P-031 → UNBLOCKED), ROADMAP, REPORT.

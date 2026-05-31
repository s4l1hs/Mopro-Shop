# Tranche 4c baseline audit (read-only)

Re-verification of the PR #27 (backend) + PR #28 (consent UX + instrumentation)
foundations this consumer PR builds on. Date: 2026-05-31. Base: `main` @ #28 merged.

## 2.1 Referenced foundations

| Foundation | State | Evidence |
|---|---|---|
| `GET /me/recently-viewed` | Exists | `cmd/core-svc/analytics_handlers.go:143` `handleRecentlyViewed` — returns `{"data": [productSummaryJSON]}` (NOT `{products,count}` as the prompt guessed); catalog-enriched, recency-ordered, `?limit` (≤50). |
| `POST /analytics/sessions/identify` | Exists | auth-required; body `{sessionId}`; backend `INSERT session_identity ON CONFLICT DO NOTHING` + projection backfill (4a). |
| `AnalyticsService` + session id | Exists | `lib/features/analytics/analytics_service.dart`: `analyticsServiceProvider`; session id persisted in SharedPreferences (`mopro_analytics_session_id`). Needs an `identify()` method + `sessionId` getter (added here). |
| `userConsentProvider` | Exists | `lib/features/analytics/user_consent_provider.dart`: `UserConsent{analyticsEnabled,...,authed,loading}`; rebuilds on auth change. |
| `ConsentBanner` + `/account/privacy` RTBF | Exists | RTBF button → `userConsentProvider.deleteAllData()` → `DELETE /me/analytics-data`. No `recentlyViewedProvider` invalidation yet (provider doesn't exist — added here). |
| PDP `product_view` emission | Exists | `product_detail_screen.dart` initState post-frame `track('product_view')` (4b). Flow CC depends on it. |
| auth provider | `authNotifierProvider` | `AsyncValue<AuthState>`; authed = `valueOrNull is AuthAuthenticated` (no `authStateProvider`/`isAuthed` — prompt names are approximate). |
| `kAnalyticsConsentEnabled` | Exists | `lib/core/feature_flags.dart`. |

## 2.2 Rail widget shape — **DECISION: sibling `ProductListRail`** (not `MoproProductRail`)

There is no `MoproProductRail`. The home rail is **`ProductRail`**
(`lib/features/catalog/widgets/product_rail.dart`) — a **`ConsumerWidget` that
watches `productsRailProvider(sort)`**; its data source is load-bearing. Adding a
`.fromList` mode would mean a ConsumerWidget that conditionally ignores its own
provider — awkward and risks the existing sort-key callers (home rails,
editors-picks).

Per §1.6 trigger #1 + §2.2, ship a **sibling `ProductListRail`** (StatelessWidget)
that renders the *same* scroller visuals (height 258, 152-wide `ProductCard`,
8dp gaps, 16dp padding, title row + optional "Tümünü gör") from a supplied
`List<ProductSummary>`. Reuses `ProductCard`; touches no existing caller. (Obvious
choice — not surfaced as a question.)

## 2.3 Home column mount

The omitted slot is the desktop-only `_EditorsPicksSection` two-column
(`home_screen.dart`), but the home `CustomScrollView` (slivers ~70+) is the
natural place for a breakpoint-agnostic rail. **Mount: a `wrap(...)`-ed
`SliverToBoxAdapter` in the main slivers list** (after the server-driven rails),
hidden when empty — visible on mobile + desktop, no column-registration system
(server rails are `homeRailsProvider`; this rail is client-driven and mounts
inline). Existing home goldens are unaffected because the rail is `shrink` when
the provider is empty (guest/no-consent — the golden states).

## 2.4 `ProductCard` reuse

`ProductCard(product: ProductSummary, onTap:)` — reused as-is. `recentlyViewedProvider`
therefore returns `List<ProductSummary>` (matches both `ProductCard` and the
endpoint's `productSummaryJSON`), not `List<Product>` as the prompt's snippet says.

## 2.5 Empty-state convention

Confirmed: optional home rails render `SizedBox.shrink()` when empty (no
placeholder). The recently-viewed rail follows suit.

## 2.6 API surface

No analytics API client exists (4b's `AnalyticsService` posts events via dio
directly). `recentlyViewedProvider` will call `dio.get('/me/recently-viewed')`
and parse `data[]` with `ProductSummary.fromJson`; identify gets an
`AnalyticsService.identify()` method (it already holds sessionId + dio).

## Scope

Small, achievable in one PR: sibling rail widget + provider + home mount +
identify wiring + RTBF invalidation + 3 flows + ~6 goldens + docs. No backend
change expected (§3 likely no-op).

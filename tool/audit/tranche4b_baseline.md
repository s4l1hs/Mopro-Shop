# Tranche 4b baseline audit (read-only)

Re-verification of every referenced foundation (the 4a retrospective lesson) +
the §2.4 substrate gap classification. Date: 2026-05-31. Base: `main` @ PR #27 merged.

## 2.1 Referenced foundations

| Foundation | State | Evidence |
|---|---|---|
| Session-5a `recentlyViewedProvider` | **Missing** (build-from-scratch) | no provider in `mobile/lib/`; confirms PR #27 audit. |
| "Son baktıkların" rail mount | **Omitted, present hook** | `home_screen.dart:108-145` — desktop `_EditorsPicksSection` renders a single `ProductRail`; the recently-viewed companion column is explicitly omitted ("no local recently-viewed history provider"). Mount = extend this sub-section. |
| PR #17 `LoginRequired` / `showAdaptiveModal` | Exists | `lib/core/widgets/login_required_sheet.dart`, `adaptive_modal.dart` (Tranche 3). Reusable for banner presentation. |
| PR #19 `AccountLeftRail` + account routes | Exists | `account_left_rail.dart` + `account_rail_item.dart` (`AccountRailItem` enum + `accountRailItemFor`). "Gizlilik" row follows the reviews/questions pattern I added in Tranche 3. |
| PR #20 A11y guard | Exists | (gates in CI; new screens must pass.) |
| PR #23 Notifications preferences screen | Exists | `notification_preferences_screen.dart` (ConsumerWidget) — shape to mirror for privacy settings. |
| PR #24 `flutter_markdown` | Exists | help articles render markdown; privacy article reuses it. |
| PR #27 analytics endpoints | Exists | `cmd/core-svc/analytics_handlers.go` — ingest (OptionalAuth), identify, GET/PUT `/me/consent`, DELETE `/me/analytics-data`, GET `/me/recently-viewed`. Consent JSON `{analyticsEnabled, consentedAt, revokedAt}`; recently-viewed `{data:[productSummaryJSON]}`. |
| `kAnalyticsConsentEnabled` build flag | **Missing** | no `feature_flags.dart`; 4a was backend-only. Create in §4.3. |
| `ProviderObserver` / `NavigatorObserver` registration | **Missing** | none registered on GoRouter or root ProviderScope. Instrumentation observers are fully greenfield + require app-boot wiring (main.dart ProviderScope `observers:` + GoRouter `observers:`). |

## 2.4 Substrate gap classification

- **`ProductRail`** (`catalog/widgets/product_rail.dart`) is **sort-key-driven**:
  `ref.watch(productsRailProvider(sort))` — it fetches its own data and cannot
  render an arbitrary product list. **Not reusable** for a `recentlyViewedProvider`-
  backed rail.
- **`ProductCard`** (`catalog/widgets/product_card.dart`) takes a
  `ProductSummary` (generated `mopro_api` DTO) + `onTap` — **reusable** as the
  rail's item.
- **Empty-state convention:** optional home rails render nothing when empty (the
  `_EditorsPicksSection` comment documents hide-when-empty); no placeholder.
- **Mount mechanics:** literally adding a widget into the home `CustomScrollView`
  (extend `_EditorsPicksSection` into a two-column row when recently-viewed has
  data). No registration system.
- **`GET /me/recently-viewed`** is hand-written (not in the OpenAPI/generated
  client), so the provider calls it via raw `dio.get` and parses `data[]` with
  `ProductSummary.fromJson`.

**Classification:** the consumer is **"new provider + a small list-driven rail
widget (reusing ProductCard) + a two-column home mount"** — medium, not trivial
("drop in a ProductRail" is ruled out because ProductRail is sort-driven).

## Scope assessment (pre-§4)

This PR spans three large, distinct surfaces plus 3 integration flows + ~10
goldens + docs:
- **Consent UX** (§4–§5): banner + `/account/privacy` settings + provider + RTBF +
  route + rail row + privacy article + DRAFT copy + build flag + a11y. Large,
  self-contained, no app-boot risk.
- **Instrumentation** (§6–§7): `analyticsService` + a **new root `ProviderObserver`**
  (interacts with all 30+ providers — §1.6 trigger #3) + a **new GoRouter
  `NavigatorObserver`** + 7 manual call sites + session-id persistence + lifecycle
  flush. Large + the riskiest (app-boot wiring, observer/provider interaction).
- **Recently-viewed consumer** (§8): provider + list-rail widget + home mount. Medium.

Realistically ~2 sessions (the design doc's combined 4a+4b estimate, with 4a
already consuming one). Per §1.6 (triggers #1 substrate build-from-scratch + #3
observer complexity) the split is pre-authorized. Surfaced to the user before §4.

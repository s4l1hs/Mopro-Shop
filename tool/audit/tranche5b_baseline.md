# Audit — Tranche 5b (Platform Growth: share + SEO + JSON-LD + sitemap + browsing-history)

Read-only baseline. Each row: file:line + observation.

## Branch-point divergence (§1.1)

- **Neither 5a nor the slug PR is merged to `main`.** `main` is at `3234ac92`
  (pre-5a). PR #31 (slug) merged into `feat/seller-facing-and-platform-growth`
  (remote tip `2699aa18`), which now holds **5a + slug**. That accumulation
  branch is still open vs main.
- **Decision:** branch `feat/platform-growth-share-seo-sitemap` off
  `origin/feat/seller-facing-and-platform-growth` (stacking), continuing the
  precedent set for the slug PR. 5b depends on both (storefront route + the
  PDP→storefront slug wiring). `make verify` green at branch-point → no §1.1
  hygiene commit.

## §2.1 Share infrastructure — ABSENT (confirmed)

- No `share_plus` in `pubspec.yaml`; no `navigator.share`; no `MoproShareButton`.
  → §4 adds `share_plus` (Flutter ecosystem standard for share intents).

## §2.2 SEO meta substrate — pure SPA shell (gates §1.6 trigger #1)

- `mobile/web/index.html:21` ships the **default Flutter placeholder**
  `<meta name="description" content="A new Flutter project.">` and
  `<title>mopro</title>` (line 32). No per-route templating, no build-time
  injection, no `MetaTagsService`.
- **Decision:** runtime DOM mutation via `dart:html` (§5). **§1.6 trigger #1 does
  NOT fire** — there's no stated hard requirement for JS-less crawlers, and the
  non-goals explicitly accept the runtime-mutation trade-off (modern crawlers
  execute JS). Documented in REPORT.
- **Drive-by (§13):** fix the placeholder `description` + `<title>` in index.html
  to real Mopro defaults (the pre-JS shell state).

## §2.3 JSON-LD — ABSENT

- No `application/ld+json`, no structured-data utilities. → §6 builds
  `StructuredDataService`.

## §2.4 Sitemap / robots — ABSENT

- No backend route matching `sitemap`/`robots`; no `mobile/web/robots.txt` or
  `sitemap.xml` static file. → §3 backend endpoint + static robots.
- **Data sources (all postgres-ecom, all core-svc modules):** `internal/catalog`
  (products + categories), `internal/seller` (sellers), `internal/help`
  (articles — confirmed in core-svc, `help_schema`). No suitable "list all for
  sitemap" methods exist yet → add a narrow `SitemapReader` per module (mirrors
  5a's `SellerStorefrontReader`; avoids cross-schema JOIN per CLAUDE.md §5 and
  avoids widening the 3 Service interfaces). Handler composes + builds XML.
- Catalog size is seed-scale (<<50k URLs) → single `sitemap.xml`; pagination
  path documented in REPORT as Backlog-when-triggered.

## §2.5 Recently-Viewed see-all dependencies

- `recentlyViewedProvider` — `lib/features/home/recently_viewed_provider.dart:88`
  (intact; `refresh()` = `invalidateSelf`). Gated on `userConsentProvider`.
- Home rail mount — `lib/features/catalog/screens/home_screen.dart:149`
  `_RecentlyViewedSliver` builds `ProductListRail` **without `onSeeAll`** (comment
  line 152: "No /account/browsing-history screen yet … omitted"). → §8.4 wires it.
- `ProductListRail.onSeeAll` exists (`product_list_rail.dart:24`) → "Tümünü gör"
  link shown when non-null.
- `AccountRailItem` enum + `accountRailItemFor` + `AccountLeftRail._authedRows`
  (`account_rail_item.dart`, `account_left_rail.dart:51`) — add a `history` entry
  near `privacy`, mirroring the `_row(...)` pattern.
- Account routes live in a `ShellRoute` (`app_router.dart:417`); add
  `/account/browsing-history` beside `/account/privacy` (auth+consent gated; the
  hard-gated list at `app_router.dart:170` already covers `/account/*`).
- Delete pattern (`privacy_settings_screen.dart:38`):
  `userConsentProvider.deleteAllData()` → `DELETE /me/analytics-data` →
  `ref.invalidate(recentlyViewedProvider)` + snackbar. Reuse for "Geçmişi sil".

## Route-shape divergence from the prompt (affects §3 sitemap + §5 canonical)

- **Products and categories are `:id`-based, not `:slug`** —
  `app_router.dart:266` `/products/:id`, `:362` `/categories/:id`. Neither
  `catalog.Product` (domain) nor the DTO has a `slug`. Sellers (`/sellers/:slug`)
  and help articles (`/help/article/:slug`) ARE slug-based.
- **Adaptation:** sitemap + canonical URLs use `/products/{id}` and
  `/categories/{id}`; `/sellers/{slug}` and `/help/article/{slug}` as the prompt
  says. The prompt's `:slug` for products/categories is aspirational (no slug
  column exists); not adding one this turn (out of scope).

## baseUrl / web origin — config gap (§4.3, §5.3)

- `apiBaseUrlProvider` (`core/di/providers.dart:13`) is the **API** origin
  (`https://api.moproshop.com`), not the web origin. Share/canonical/sitemap need
  the **web** origin. → add `webBaseUrlProvider` (`WEB_BASE_URL` dart-define,
  default `https://mopro.shop` per §3.2's robots example). Backend sitemap host
  via env too.

## Baselines (§1.3)

- `go test ./...`: green. `flutter analyze`: clean (0 issues).
- `flutter test`: 556 pass / 121 fail where all 121 are the macOS golden platform
  guard (Linux-baselined) — established 5a baseline.
- `flutter build web --release`: `main.dart.js` ~4.73 MB (slug PR). +6% budget
  ⇒ ceiling ~5.01 MB.
- Parity ~54–55% post-5a.

## §1.6 disposition

No trigger fires at audit. Default = single PR. Trigger #3 (budget) re-evaluated
at the §5/§6 boundary; if hit, split share+see-all (shipped) vs
SEO+JSON-LD+sitemap (carried) — but sitemap (§3) ships regardless as it's
backend-self-contained.

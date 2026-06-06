# Trendyol Parity Audit — 2026-06-03 — PR #77

> **Step 5 of the five-step audit-then-fix plan. Audit-only — NO UI changed in this PR.**
> Parity work lands in follow-up PRs scoped from §6, referencing the `P-ID`.
> **Trendyol snapshot date: 2026-06-03** (see §2.4 — the reference moves; this audit is against this snapshot, not future Trendyol).

---

## TL;DR

- **CONFIRMED HIGH: 0.** The two findings that *would* have been HIGH on a green-field app — design-token systematization (§4.1) and auth-gate consistency (§4.4) — are **already VERIFIED-COMPLETE**. Mopro is a mature implementation, not a skeleton.
- **CONFIRMED MED: 3** — P-007 (PDP lacks delivery-estimate, Mopro-side confirmed), P-020 (dark-mode AA contrast fail, already gate-tracked "Backlog"), P-026 (search/PLP filters render but are inert — don't re-query).
- **CONFIRMED LOW: 6** — P-004 (card favorites-count, both sides), P-005 (card token-drift), P-006 (discount-pill inconsistency), P-011 (cart: no promo/suggestions/save-for-later), P-013 (favorites flat list), P-014 (hardcoded strings). P-011/P-013 are confirmed absent Mopro-side; their *Trendyol* comparison is PROBABLE.
- **PROBABLE: 3 findings** — P-009 (MED, search-card merch badges), P-012 (LOW, checkout flow-shape), P-015 (LOW, PDP variant/size-guide). **Plus, by the coverage constraint, the *Trendyol-side comparison* for ~19 of 20 surfaces** (403 / login-gated) — the Mopro side of those is CONFIRMED.
- **UNKNOWN: 2** — U-001 (Trendyol parametrized-page exact metrics, 403-blocked), U-002 (Trendyol mobile-app-only surfaces: stories, live shopping — not web-fetchable).
- **VERIFIED-COMPLETE surfaces (12):** Design tokens · Global navigation (bottom nav + web header) · Home composition · Product card · Flash deals · PDP structure · Search/PLP filters+sort · Reviews · Q&A · Orders/Returns/Refund · Notifications · Empty/loading/error · Responsive · Auth-gate. (Listed with evidence in §5.)
- **Recommended NOW sequence:** **P5-1** (card+PDP fidelity polish: P-005 token-drift + P-006 discount-pill consistency + P-014 hardcoded-string sweep — pure UI, no API dep, no auth, ~300 LOC) → **P5-2** (dark-mode contrast token fix: P-020 — tiny token tweak + contrast-gate flip). Both fully CONFIRMED, zero dependencies. Everything else is SOON/LATER and either backend-data-gated or PROBABLE-pending-confirmation.

**Build status (2026-06-04):** **P-005, P-006, P-020 RESOLVED** (P5-1/P5-2). **P-014 ✅ CLOSED** — the full
i18n hardcoded-string sweep landed across **7 phased PRs** (#79 app_router · #80 auth+sipay · #81 account ·
#82 verification+marketing · #83 checkout+singletons), ~250+ strings, 0 hardcoded TR left in UI sinks. The
arc's lessons (full-file reads, key+JSON test pattern, const→build-time, golden-prediction, diacritic-undercount,
orphaned-widget) are the canonical i18n template. **P-026 closed as `BLOCKED-BY-BACKEND-GAP`**, then **P-028 ✅ RESOLVED**
(`feat/catalog-filter-api`) — the catalog/search backend now filters (price/brand/rating/free_shipping/in_stock/
category) + sorts (5 tokens) end-to-end; the `bestseller` sort is carved to **P-029** (cross-schema popularity). **P-026
is now unblocked. **Step-5 findings: P-005, P-006, P-020, P-014, P-028, P-026 resolved · P-015 FIXED (OOS variant
chips) · P-011 CORRECTED · P-004/P-009/P-012/P-013 NOT-ACTIONABLE (backend-gated / documented-design / PARK) ·
HeroCarousel REMOVED · P-029 opened. ProductSummary enriched (`feat/productsummary-enrich`) **then P-004 + P-009
✅ RESOLVED** (`feat/wire-card-badges`): the card now renders the favorites-count overlay + free-shipping/discount
badges end-to-end. `discount_pct` emitted; `lowest_30d_price` → **P-030** (HIGH, compliance). **P-029 bestseller
✅ RESOLVED end-to-end** (backend `feat/bestseller-sort`, Pattern B in-process global scope; frontend un-hide
`feat/bestseller-unhide`; category-scope → **P-031**). **P-030 price-history ✅ RESOLVED end-to-end**
(backend `feat/price-history` Mechanism B trigger; card display `feat/lowest-30d-display`; PDP per-variant
display + **P-032 ✅ price-update lifecycle** `feat/price-update-lifecycle` — seller-scoped
`PUT /seller/variants/{id}/price`). **P-033 ✅ RESOLVED** (`product_view` carries `categoryId`) →
**P-031 ✅ RESOLVED end-to-end** (`feat/category-aggregation`: per-category `RebuildPopular` pass +
`PopularProductIDsInCategory` + handler routing with global fallback — completing P-029→P-033→P-031).
**P-007 ✅ RESOLVED** (PDP delivery-ETA shipped end-to-end). **P-034 ✅ SUPERSEDED** — its shipping-ETA
infra (seller `dispatch_city`, seeded `ref_schema` zone/transit lookup, cheap `shipping.EstimateETA`,
`PdpDeliveryInfo` widget) was built directly in the P-007 PR rather than as a separate carve.
**🎉 ALL PARITY FINDINGS CLOSED END-TO-END.** Remaining is post-audit polish/infra only (not parity gaps):
chi-square flake (#74), PDP-strikethrough (minor), analytics-integration + delivery-ETA live-PG tests in
`make verify`, PDP-goldens Linux regen.**

**Honest headline:** *the visual/interaction language is already Trendyol-shaped.* The original ask ("make UI look like Trendyol; preserve guest browsing; gate only personal actions") is **substantially met** — guest browsing + the auth gate are a model implementation (§4.4). Remaining parity work is **fidelity polish + backend-data wiring**, not surface-building. This is the §12 "concentrated / coverage-constrained" outcome, not the "8 HIGH" outcome.

---

## Methodology

Per the Step-5 prompt §2, adapted for visual work. Evidence types, in descending fidelity:

1. **Widget-code evidence** — the Flutter widget for the surface, cited `file:line`. The highest-fidelity answer to "what does Mopro render *today*?" All Mopro-side CONFIRMED claims in this audit were read on this branch (`docs/trendyol-parity-audit`, off `origin/main@0a5b763c`).
2. **Golden-test evidence** — the platform-tagged goldens (`mobile/test/_support/golden_platform.dart` harness from the Step-3 tooling arc). 149 golden PNGs exist across 22 golden suites; cited by path. **Golden-coverage gaps are themselves findings** (noted per surface).
3. **Trendyol web evidence** — `WebFetch` of public pages. **Coverage constraint (important):** only `https://www.trendyol.com` (homepage) returned rich SSR structure on 2026-06-03. `https://www.trendyol.com/sr?q=…` (search) returned **HTTP 403**; `/cok-satanlar` returned meta-only. Trendyol bot-protects parametrized pages. **Consequence: only the HOME surface has CONFIRMED Trendyol-side evidence; every other surface's Trendyol comparison is PROBABLE (general knowledge of Trendyol patterns) and explicitly marked.**
4. **General-knowledge evidence** — used only for PROBABLE findings, never CONFIRMED (prompt §2.1 / §10).
5. **User-supplied screenshots** — none supplied during this audit window; the prompt (§2.1, §10) says this is fine and the affected findings are PROBABLE.

**CONFIRMED requires evidence type 1, 2, or 3 on BOTH sides.** Where Mopro is read (1/2) but the Trendyol equivalent is general-knowledge (4), the *gap* is **PROBABLE**, not CONFIRMED — even when the Mopro side is certain.

**Memory is a hypothesis (prompt §2.5).** This audit already caught two memory-errors the prompt's own examples assumed: the prompt's sample finding "P-007 — Mopro's buy box lacks sticky positioning" is **false** — `mobile/lib/features/catalog/widgets/pdp/pdp_sticky_cta.dart` exists and is wired (see §3.5). And the early project memory implied a thin UI; the real tree has 149 goldens and a complete design system. Both were corrected by reading, not trusting recall.

---

## §2.3 Surface coverage matrix

"Mopro widget" = a real widget read on this branch. "Golden" = a platform-tagged golden PNG exists. "TY ref" = was the Trendyol equivalent fetchable on 2026-06-03? "Conf." = the audit's confidence in the *gap assessment* for that surface.

| Surface | Mopro widget? | Golden? | TY ref accessible? | Conf. |
|---|---|---|---|---|
| Home / Landing | yes (`features/catalog/screens/home_screen.dart`) | yes (`home_{mobile_375,tablet_768,desktop_1440}`) | **yes (homepage)** | CONFIRMED |
| Global nav — bottom (mobile) | yes (`shell/app_shell.dart`) | yes (`shell/goldens/bottom_nav_*`) | partial (home header) | CONFIRMED |
| Global nav — web header | yes (`shell/web_header.dart`) | yes (`shell/goldens/web_header_{1024,1440}_*`) | yes (homepage header) | CONFIRMED |
| Search results | yes (`catalog/screens/search_screen.dart`) | yes (`catalog/search_goldens_test`) | **no (403)** | PROBABLE |
| Category browse | yes (`catalog/screens/category_products_screen.dart`) | yes (`catalog/plp/goldens`) | **no (403/meta-only)** | PROBABLE |
| PDP | yes (`catalog/screens/product_detail_screen.dart` 950 LOC) | yes (`catalog/pdp/goldens`) | **no (403-class)** | PROBABLE (Mopro side CONFIRMED) |
| Reviews | yes (`catalog/pdp/reviews/*`) | yes (`reviews/goldens`) | no (PDP-embedded) | PROBABLE (Mopro CONFIRMED) |
| Q&A | yes (`catalog/pdp/qa/*`) | yes (`qa/goldens`) | no (PDP-embedded) | PROBABLE (Mopro CONFIRMED) |
| Cart | yes (`features/cart/` 15 files) | yes (`cart/widgets/goldens/cart_line_card`) | no (login-gated) | PROBABLE (Mopro CONFIRMED) |
| Checkout | yes (`features/checkout/` 13 files) | no | no (login-gated) | PROBABLE (Mopro CONFIRMED) |
| Account / Profile | yes (`features/account/` 16 files) | yes (`account/goldens/account_{profile,security,welcome}`) | no (login-gated) | PROBABLE (Mopro CONFIRMED) |
| Orders / Returns | yes (`features/order/` 21 files) | yes (`order/goldens/{returns_list,refund_card,timeline}`) | no (login-gated) | PROBABLE (Mopro CONFIRMED) |
| Favorites | yes (`features/favorites/` 2 files, 220 LOC) | yes (`favorites/goldens`) | no (login-gated) | PROBABLE (Mopro CONFIRMED) |
| Auth flow | yes (`features/auth/` 15 files) | yes (`auth/goldens/auth_card`) | partial (login page not fetched) | PROBABLE (Mopro CONFIRMED) |
| Notifications | yes (`features/notifications/` 8 files) | yes (`notifications/goldens/*`) | no (login-gated) | PROBABLE (Mopro CONFIRMED) |
| Help / Contact | yes (`features/help/` 10 files) | yes (`help/goldens`) | no (not fetched) | PROBABLE (Mopro CONFIRMED) |
| Empty/loading/error | yes (`core/widgets/{empty_state,loading_spinner,error_banner}`, `widgets/skeleton_box`) | partial (per-surface) | n/a | CONFIRMED (Mopro) |
| Accessibility | yes (`design/a11y_contrast.dart`, theme 48px targets) | n/a (contrast test gate) | n/a | CONFIRMED |
| Responsive | yes (`design/responsive/*`) | yes (375/768/1024/1440 across suites) | n/a | CONFIRMED (Mopro) |
| Seller panel | yes (`features/seller/` 13 files) | yes (`seller/goldens/*`) | no (seller-gated) | PROBABLE (Mopro CONFIRMED) |

**Matrix summary:** 20 surfaces have a real Mopro widget; 18 have golden coverage (checkout + a couple cross-cutting lack goldens — minor coverage gap, see P-019 note). **Trendyol-side: 1 CONFIRMED-accessible (home), ~19 PROBABLE/UNKNOWN** (403 / login-gated). This is the audit's dominant uncertainty and the reason most per-surface gaps are PROBABLE despite the Mopro side being certain.

---

## §3.1 Home / Landing findings

Mopro home (`mobile/lib/features/catalog/screens/home_screen.dart:75-132`) mounts, in order: `MoodStoriesStrip` → `_BannerCarousel` → `FlashDealsRail` → `HomeCategoryGrid` → `TrustBar` → dynamic backend-driven `ProductRail`s (popular/bestseller equivalents, keyed `r.key`) → `_RecommendationsSliver` (personalized) → `_RecentlyViewedSliver` → `_EditorsPicksSection` → `HomeFooter`. Goldens: `home_mobile_375.png`, `home_tablet_768.png`, `home_desktop_1440.png`.

Trendyol home (fetched 2026-06-03) shows: header (logo/search/account/cart + top links "Bugün Fiyatı Düşenler / Yemek / Ayrıcalıkları Keşfet") → campaign quick-links strip → **Popüler Ürünler** (grid, cards carry rating + price + favorites-count) → **Flaş Ürünler** (countdown "00:00:00") → **Çok Satan Ürünler** → **discount-tier nav (5/10/30/50%)** → category-discount promos → "Bunlar da İlginizi Çekebilir" search-category chips → extensive footer.

### P-003 — Home section composition is at parity (with one intentional divergence)
**Status: STRUCTURAL | Severity: — | Confidence: CONFIRMED → VERIFIED-COMPLETE**
Evidence: Mopro `home_screen.dart:75-132` (read); Trendyol homepage (WebFetch 2026-06-03).
Mopro covers every Trendyol home structural element: hero ✓, flash-deals-with-countdown ✓ (§3.1/P-008), category grid ✓, popular/bestseller rails ✓ (dynamic `ProductRail`), recommendations ✓, footer ✓ — **plus** Mopro-only mood-stories, recently-viewed, editors'-picks rails.
**Verdict:** VERIFIED-COMPLETE. The one Trendyol element Mopro omits — the **discount-tier nav (5/10/30/50% off)** — is an **intentional divergence** (D-002): Mopro's model is perpetual cashback, not discount tiers (CLAUDE.md §1). Per prompt §1.3/§10 this is documented, **not filed as a gap**.

### P-008 — Flash-deals rail matches Trendyol "Flaş Ürünler" including live countdown
**Status: INTERACTION | Severity: — | Confidence: CONFIRMED → VERIFIED-COMPLETE**
Evidence: `mobile/lib/features/home/widgets/flash_deals_rail.dart:30-119` — a 1-second `Timer.periodic` drives an `HH:MM:SS` countdown (`_fmt`, line 49-52) in a brand-orange header, with an "ended" collapse state (line 60-71); responsive body (mobile horizontal scroller / tablet 3-col / desktop 5-col, line 134-165); flash price via `ProductCard.priceOverride`. Goldens: `home/goldens/flash_deals_mobile_375.png`, `flash_deals_desktop_1440.png`. Trendyol: "Flaş Ürünler … countdown timer showing 00:00:00" (WebFetch 2026-06-03).
**Verdict:** VERIFIED-COMPLETE — corrects any assumption that flash-deals/countdown is missing.

### P-004 — Product card lacks favorites-count social proof
**Status: CONTENT/VISUAL | Severity: LOW | Confidence: CONFIRMED (both sides)**
Evidence: Mopro `ProductCard` (`product_card.dart:88-98`, read) has a favorite *toggle* (heart, guest-local) but **no favorites count**. Trendyol home cards show a favorites count by the heart (WebFetch 2026-06-03: "Popüler Ürünler … with ratings, prices, and **favorites counts**"). This is one of the few findings CONFIRMED on both sides — Trendyol *home* was the one fetchable surface.
Gap: missing social-proof favorites count on the card.
Severity: LOW (social-proof nicety; not conversion-blocking).
Recommendation: bundle with `P5-4` (`feat/parity-card-badges`) — render a count when the catalog API exposes one. **Backend dependency:** needs a favorites-count field on the product summary.
**Outcome (NOT-ACTIONABLE — `chore/step5-low-batch`):** backend-gated — `ProductSummary` (mopro_api) exposes no favorites-count field; the card UI is correct (cf. P-008b data-dark pattern). Needs a catalog `ProductSummary` enrichment (favorites_count) to render. No code change.
**Outcome 2 (✅ BACKEND-UNBLOCKED — `feat/productsummary-enrich`):** `ProductSummary` now emits `favorites_count` (a same-schema subquery over `catalog_schema.user_favorites` + index migration 0082 — no cross-schema JOIN). Frontend wiring (count by the heart on card/PDP) is a small follow-up.
**✅ RESOLVED (frontend — `feat/wire-card-badges`):** the product card renders a `♥{count}` social-proof overlay (`formatCompactCount`: <10 hidden, 10–999 raw, ≥1000 "1.2K"), populated on every card surface (list/search/rails/flash/favorites — the custom `productSummaryFromApi` mapper updated too). The finding is **card-scoped** (per its title); the PDP uses the un-enriched full `Product` and is out of scope (a backend follow-up, not part of P-004).

---

## §3.2 Global navigation findings

### P-002 — Bottom nav + web header at parity
**Status: STRUCTURAL/VISUAL | Severity: — | Confidence: CONFIRMED → VERIFIED-COMPLETE**
Evidence — mobile bottom nav (`mobile/lib/shell/app_shell.dart:83-129`): 5 tabs — Home (`home_outlined`), Categories (`grid_view_outlined`), Favorites (`favorite_border_rounded`), Cart (`shopping_bag_outlined`), Account (`person_outline_rounded`), all i18n (`nav.*.tr()`). Goldens `shell/goldens/bottom_nav_{light,dark}.png`. This mirrors Trendyol's 5-tab mobile nav (Anasayfa/Kategoriler/Favoriler/Sepetim/Hesabım).
Evidence — web header (`mobile/lib/shell/web_header.dart:57-100`): logo (left) · `WebSearchPill` (center, with `SearchSuggestionsDropdown`) · favorites icon · **cart icon with live badge** (`cartCountProvider`, line 41/91) · account hover menu · MegaMenuBar. Goldens `shell/goldens/web_header_{1024,1440}_{light,dark}.png`, `account_hover_menu_{authed,guest}_1440_light.png`, `search_suggestions_populated.png`. Trendyol homepage header (WebFetch) shows the same logo/search/account/cart arrangement.
**Verdict:** VERIFIED-COMPLETE. Search-everywhere (§4.3) is satisfied — search is 1 tap from every surface (bottom-nav-adjacent on mobile, persistent pill on web).

---

## §3.3 Search results findings

Mopro: `catalog/screens/search_screen.dart` (253 LOC, read) + `catalog/widgets/search_input.dart`, results render `ProductCard` in a grid (`CatalogShell`), with `filter_sheet.dart` (239), `plp/widgets/filter_panel.dart` (377), `plp_filter_chips.dart` (86), `sort_sheet.dart` (71). Goldens: `catalog/search_goldens_test.dart`. **Trendyol `/sr?q=elbise` returned HTTP 403** — Trendyol-side is general-knowledge only.
CONFIRMED Mopro internals (`search_screen.dart`, read): **empty/pre-query state** (`_EmptySearchBody`, line 154) = removable recent-search chips + clear-all (`search.recent_searches`/`search.clear_recent`) + 8 root-category `ActionChip` suggestions (`search.suggested_categories`) — matches Trendyol's pre-query suggestions. **Pagination = load-more** (`hasMore`/`loadingMore`/`loadMoreError`/`onLoadMore`, line 76-79), not infinite-scroll or paged. Mobile = 2-col `CatalogShell`; tablet/desktop = 280px `FilterPanel` sidebar + query chip + `PlpFilterChips` + 3/5-col grid (line 95-143).

### P-026 — Search filters are rendered but inert (don't affect the fetch yet)
**Status: ✅ RESOLVED — frontend wired to the P-028 backend (`feat/wire-frontend-filters`) | Severity: MED | Confidence: CONFIRMED**
Evidence: `search_screen.dart:88-91` — "Filters write the plp substrate keyed by the query; **like PLP, they don't yet affect the search fetch** (REPORT §5)." So the filter panel + chips render and persist, but selecting a filter does not re-query.
Gap: filter UI present but functionally disconnected on search (and PLP).
Severity: MED — a visible control that doesn't work is worse than an absent one; affects the core browse loop.
Recommendation: `P5-wire-filters` — connect `plp_filters_provider` selections to the search/PLP fetch. **Backend dependency:** the catalog/search API must accept the filter params. Already a known item (REPORT §5) → not a new surface, a wiring follow-up.
**Resolution (discover-and-bifurcate, branch `feat/wire-plp-filters`):** closed as `BLOCKED-BY-BACKEND-GAP`. Discovery (`docs/internal/p026-filter-wiring.md`) traced every dimension through all six layers (spec → client → provider → handler → service → repo): the frontend is fully built, but `/products` + `/search` apply no filter or sort — even spec-declared params (`sort` on both; `min_price`/`max_price`/`category_id` on `/search`) are dropped at the handler, and `catalog.Service`/repo have no filter args. No dimension can be wired end-to-end without backend work → **no frontend wiring shipped**. Full-stack gap filed as **P-028 (HIGH, backend)**; the frontend-wiring PR is queued behind it (the `PlpFilters` substrate + URL codec are ready — discovery §9).
**Resolution 2 (frontend-wiring, `feat/wire-frontend-filters`):** ✅ FULLY RESOLVED. With P-028's filter-aware API live, `filteredProductsProvider` now watches the whole `PlpFilters` and `searchProvider` reads the query-keyed filter — both pass price/brand/rating/free_shipping/in_stock/sort to the API, and the result list rebuilds on every filter/sort change. The already-wired `PlpFilterChips` + clear-all are now live; `CatalogShell`'s empty path is reached when over-filtered. UI calls (discovery §10): `bestseller` **hidden** from the sort selectors (it would duplicate "Recommended"; backend maps it→recommended; enum + key kept for P-029); `cashback_only` **disabled** with an informational hint (vacuous server-side). `in_stock` added to `PlpFilters` + codec + bridge + chip. 4 wiring tests. The original gap ("filters render but are inert") is closed.

### P-028 — Catalog/search API applies no filter or sort dimension (blocks P-026)
**Status: ✅ RESOLVED (partial — `bestseller` sort carved to P-029) | Severity: HIGH | Confidence: CONFIRMED | Type: backend (full-stack)**
Evidence (read, `feat/wire-plp-filters` discovery): `cmd/core-svc/catalog_handlers.go:53-121` — `handleListProducts` reads only `category_id`/`page`/`per_page`/`market`; `handleSearch` reads only `q`/`page`/`per_page`/`market`. `internal/catalog/api.go:30-31` — `ListProductsByCategory` / `SearchSummary` carry no `sort` or filter parameter; the repository (`repository.go:307`) likewise. The mobile client is partly ahead of the backend: `search_api.dart:44-85` already sends `min_price`/`max_price`/`category_id`/`sort` and `openapi.yaml:894-948` declares them ("Full-text product search with filters") — but the handler drops them.
Gap: no price / brand / rating / free-shipping / sort filtering server-side, on either endpoint.
Severity rationale: HIGH (bumped from P-026's MED) — a multi-dimension, both-endpoint, full-stack feature (spec + handler + service + repo SQL; `free_shipping` needs a new `ProductSummary` field) blocking the core browse loop's refinement. Not a one-line wiring.
Recommendation: `P-catalog-filter-api` — implement `sort` (`ORDER BY`) + `price`/`brand`/`rating` (`WHERE`) + `free_shipping` (new flag) on both endpoints; reconcile the `PlpSort` token mismatch (`bestseller`≠`best_selling`, `cashback_desc` absent — discovery §8). Then unblock P-026's frontend-wiring PR. Out of Step-5 (UI) scope.
**Resolution (`feat/catalog-filter-api`):** ✅ RESOLVED (partial). Shared reusable filter params now declared on both `/products` + `/search`; `handleListProducts`/`handleSearch` parse them; `catalog.Service`/`Repository` thread a `ProductFilter`; the repo builds parameterized WHERE (`price`/`brand`/`rating`/`free_shipping`/`in_stock`/`category`) + an `ORDER BY` switch. `rating_avg`/`brand` reuse existing `catalog_schema.products` columns (no cross-schema JOIN); migration 0081 adds `products.free_shipping` (additive DEFAULT FALSE — data population is a follow-up, the P-008b "filter ready, data SOON" pattern). Sort reconciled: spec lists the implemented set `[recommended,newest,price_asc,price_desc,cashback_desc]`; unknown tokens fall back to `recommended` (never errors). 19 integration subtests (filters + sort + search). **`bestseller` sort carved → P-029** (cross-schema popularity). **`cashback_only` excluded** (vacuous — every Mopro product earns cashback). Full evidence: `docs/internal/p028-filter-sort-api.md`. **P-026 is now UNBLOCKED** — its frontend-wiring PR can proceed (hide `bestseller` until P-029).

### P-029 — `bestseller` product sort needs catalog-side popularity (carved from P-028)
**Status: ✅ RESOLVED end-to-end (backend Pattern B + frontend un-hide) | Severity: MED | Confidence: CONFIRMED | Type: backend + frontend**
Evidence: the frontend `PlpSort.bestseller` token has no data source in `catalog_schema`. Popularity lives in `analytics_schema.popular_products` (migration 0080 — per-scope `view_count` ranking), and CLAUDE.md §5 forbids cross-schema JOINs (only `ref_schema` is exempt). P-028's `orderByClause` therefore maps `bestseller` → `recommended` (graceful), and the spec omits the token (stays honest).
Gap: no `bestseller` ordering server-side.
Recommendation: denormalize a popularity counter into `catalog_schema.products` (event/outbox sync from the analytics pipeline, or a periodic projection refresh), then add a `bestseller` `ORDER BY` arm + re-add the spec enum value. Until then the frontend should hide/disable the `bestseller` sort option.
**Resolution (`feat/bestseller-sort`, Pattern B):** the cross-schema constraint doesn't bite — analytics is an **in-process** core-svc module and `analytics.Service.PopularProductIDs` is already wired in. The catalog **handler** reads the global popularity ranking and passes ordered IDs to the repo via `ProductFilter.PopularIDs`; the repo orders by `array_position(...) NULLS LAST, p.id DESC` (all rows, popular-first — no empty PLPs). Two in-process reads combined in Go — **no cross-schema JOIN, no schema change, no sync infra** (Pattern A's denormalization was the wrong trade in-process). Spec re-adds `bestseller`; empty popularity → recommended (graceful). Evidence: `docs/internal/p029-bestseller-architecture.md`. **Global scope only** → category-scoped bestseller is **P-031**.
**Frontend un-hide (`feat/bestseller-unhide`):** removed the two `.where(... != bestseller)` filters PR #86 had added (mobile `SortSheet` + desktop `PopupMenuButton`); the option now renders in every selector and `sort=bestseller` flows to the backend (sent as a raw string — no dependency on the client regen). i18n keys already existed and match the home bestseller rail (`"Çok satanlar"`/`"Best sellers"` — kept, not the prompt's assumed "En Çok Satan"); URL codec already round-trips. Zero golden flips (the option only renders in the tapped overlay; goldens capture the closed sidebar). Evidence: `docs/internal/p029-frontend-unhide.md`. **P-029 is now closed end-to-end.**

### P-031 — category-scoped bestseller popularity (carved from P-029)
**Status: ✅ RESOLVED end-to-end (Outcome A, all components) | Severity: MED | Confidence: CONFIRMED | Type: analytics + backend**
**Resolution (`feat/category-aggregation`):** completes the chain **P-029** (global bestseller) → **P-033** (`product_view` carries `categoryId`) → **P-031** (per-category aggregation + scoped read + routing). `RebuildPopular` runs a second same-tx pass — top-`limit`-per-category (`ROW_NUMBER` window) writing `scope='category:<id>'` from the categoryId on `product_view` payloads (pure same-schema `GROUP BY`, **no catalog JOIN**, §5 honored). `Repository.PopularCategoryIDs` + `Service.PopularProductIDsInCategory` (additive sibling — global signature untouched). `applyBestsellerOrder` routes by the category (passed explicitly, since the category-PLP keeps it out of `ProductFilter`): category-scope → **global fallback on empty** (most categories until events accrue — never regress to recommended) → recommended. No migration (scope column existed), no frontend (#86), no event change (#99). Integration test (per-category ranking + cross-category isolation + global) validated on PG; handler routing unit-tested. Evidence: `docs/internal/p031-category-aggregation.md`.
Evidence: `analytics.Repository.RebuildPopular` (`api.go:98`) computes only the `'global'` scope; `popular_products` supports `'category:{id}'` scopes by schema but they're unbuilt, and `PopularProductIDs` is global-only. So P-029's bestseller sorts a category PLP by **global** popularity (a reasonable proxy), not category-specific popularity.
Recommendation: extend `RebuildPopular` to populate `category:{id}` scopes + add a scoped `PopularProductIDs(scope, limit)`; the catalog handler then passes the category scope so category-PLP bestseller is category-specific. Out of P-029's scope (analytics computation change).
**Discovery (`feat/category-popularity`, Outcome C):** the schema is already category-ready (no migration needed), but the aggregation source — `product_view` events in `analytics_schema.analytics_events` — carries **only `productId`**, no `categoryId`, and there is no category column / product→category projection anywhere in `analytics_schema`. True per-category aggregation (`GROUP BY category, product`) would therefore need a **cross-schema JOIN to `catalog_schema.products` (CLAUDE.md §5 — forbidden)** or event enrichment (frontend/ingest — out of scope). The codebase already documents this deferral ("…once categoryId is carried on the product_view payload (Backlog)"). **Decision: discovery-only — the global proxy is retained** (a niche-category leader that isn't globally popular is the only mis-rank). The enabler is filed as **P-033**; once it lands, P-031 is a small same-schema follow-up. Evidence: `docs/internal/p031-category-popularity.md`.

### P-033 — `product_view` events lack `categoryId` (blocks category-scoped popularity) (carved from P-031)
**Status: ✅ RESOLVED (Outcome A — additive) | Severity: MED | Confidence: CONFIRMED | Type: analytics + frontend**
Evidence: `requiredPayloadFields[EventProductView] = {"productId"}` — the `product_view` payload has no `categoryId`, so per-category popularity (P-031) can't be derived without a §5-forbidden cross-schema JOIN. The `popular_products.scope` column was designed for `'category:{id}'` but the data can't be built until the event carries the category.
Recommendation: have the client emit `categoryId` on `product_view` (PDP/card know the category), add it to `requiredPayloadFields`/validation, then `RebuildPopular` can populate `'category:{id}'` rows via a pure same-schema `GROUP BY (payload->>'categoryId'), (payload->>'productId')` and `PopularProductIDs` can take a scope — unblocking **P-031** with no §5 issue.
**Resolution (`feat/event-categoryid`, Outcome A additive):** the mobile PDP `product_view` emit now carries `categoryId` (the loaded `Product` always has it — no edge case). It is **optional, not required** (`ValidateBatch` is presence-only and already accepts extra keys; old/offline clients + web omit it) — so no `requiredPayloadFields` change, no migration (JSONB), no value-validation (out of the presence-only convention). Backend documents categoryId + a contract test pins the additive behaviour. **Web is a no-op** (it emits no `product_view` to the in-house pipeline — a separate web/mobile analytics-parity gap, not P-033). Evidence: `docs/internal/p033-event-categoryid.md`. **P-031 is now unblocked** — a small same-schema follow-up.

### P-030 — `lowest_30d_price` needs price-history infrastructure (carved from ProductSummary enrichment)
**Status: ✅ RESOLVED end-to-end (backend + cards + PDP + price-update lifecycle) | Severity: HIGH | Confidence: CONFIRMED | Type: backend + frontend / compliance**
Evidence (`feat/productsummary-enrich` discovery): no `price_history` / price-snapshot table exists in `catalog_schema` (or anywhere). `lowest_30d_price` (the "son 30 günün en düşük fiyatı" copy) is a **TR consumer-protection + EU** requirement, not just parity. It needs a `price_history` table + a snapshot mechanism (on-price-change hook OR a periodic snapshot job) + a cron-placement decision (which binary owns the snapshot) — >500 LOC + new infra (out of the enrichment PR's scope + its anti-goals).
Recommendation: dedicated PR — `catalog_schema.price_history` + snapshot mechanism + a 30-day-min query on `ProductSummary`. Compliance-serious → prioritize over pure-parity items.
**Resolution (`feat/price-history`, migration 0083):** discovery corrected the design — **price lives on `variants`** (not `products`), there is **no price-update path** (variants are immutable post-creation), and the dominant write is **SQL seeds**. So application-level tracking (Mechanism A) was rejected for **Mechanism B**: an `AFTER INSERT OR UPDATE` trigger on `catalog_schema.variants` feeds `variant_price_history` (backfilled on migration), and `ProductSummary.lowest_30d_price_minor` reads `MIN(price_minor) WHERE effective_at >= now()-30d` as an inline correlated subquery (mirrors `favorites_count`). Spec + clients regenerated. **Backend foundation only — NOT a compliance sign-off:** today `lowest_30d == current price` for every product (no price-update lifecycle yet → **P-032**), and the static `original_price_minor` strikethrough is still unsubstantiated by history (frontend display + legal review pending). Evidence: `docs/internal/p030-price-history-architecture.md`; convention 8 in `docs/internal/financial-core.md`.
**Frontend display (`feat/lowest-30d-display`):** the **product card** now renders "Son 30 günün en düşük fiyatı: X" (reusing the existing `product.lowest_30d` key) when a reduction is announced and `lowest_30d < price`; suppressed otherwise — so it stays dark on all current data (lowest_30d == price everywhere) until **P-032** lands. The rail summary mapper carries the field too. **PDP display is deferred (backend-blocked):** `PdpPriceBlock` already has the slot, but the PDP uses the full `Product` from `GetByID`, which does not expose `lowest_30d` (it's only on `ProductSummary`); wiring it needs a backend change to the product-detail path — folded with the P-032 reach. Evidence: `docs/internal/p030-frontend-display.md`.
**PDP display (`feat/price-update-lifecycle`):** the PDP now carries **per-variant** `lowest_30d` (the PDP shows a specific variant, so a product-level MIN would mis-display) — added to `loadVariants`/`Variant`/spec; `PdpPriceBlock` renders the existing slot when `lowest_30d < price`. **P-030 is now end-to-end** (cards #93 + PDP + the P-032 lifecycle that lets prices move). Minor open nuance: the PDP buy-box still has no strikethrough (the `Variant` model lacks `original_price`), so the PDP gates on `lowest_30d < price` rather than the card's `hasDiscount && lowest_30d < price` — a small follow-up (add `original_price` to the variant for PDP discount parity).

### P-032 — no price-update lifecycle (variants immutable; history can't yet diverge) (carved from P-030)
**Status: ✅ RESOLVED (seller-scoped price-update endpoint) | Severity: MED | Confidence: CONFIRMED | Type: backend / compliance**
Evidence: catalog has no variant price-**update** path — the only write is `InsertVariant` (create); `original_price_minor` is set only by SQL seeds. So `variant_price_history` (P-030) only ever holds the create/backfill baseline, and `lowest_30d == current price` for every product. The Omnibus 30-day rule becomes meaningful only once prices actually move over time **and** the strikethrough display is driven by tracked history rather than the static `original_price_minor` MSRP.
Recommendation: introduce a variant price-update path (seller/admin) — the trigger already captures it — and a policy + frontend decision to drive discount display from `lowest_30d_price` (assert a reduction only when `lowest_30d < price`). Legal review of the interpretation.
**Resolution (`feat/price-update-lifecycle`):** discovery corrected "admin" → **seller-scoped** (the established `RequireSellerRole` model owns price changes). `PUT /seller/variants/{id}/price` (`requireAuth + requireSellerRole`, idempotency per §4.4) → `catalog.UpdateVariantPrice`: a single `UPDATE` with **ownership enforced in SQL** (0 rows ⇒ `ErrVariantNotFound`/404, no cross-seller leak), validating `price > 0` / `original >= price`. The #92 `variants_price_history_trg` records history automatically (no manual writes). Order/ledger-safe (price snapshots at order time). Prices are now mutable, so the dormant card + PDP lines activate the moment a seller changes a price. Evidence: `docs/internal/p032-price-update-lifecycle.md`; convention 8 in `docs/internal/financial-core.md`. **Not a compliance sign-off** — whether `original_price` is substantiated by history remains a legal/policy call.

### P-009 — Search-result cards likely lack Trendyol merch badges (Kargo Bedava / campaign / "Çok satan")
**Status: CONTENT/VISUAL | Severity: MED | Confidence: PROBABLE**
Evidence: Mopro `ProductCard` (`product_card.dart`, read; see §3.1/P-004) renders heart + brand + title + rating + discount-% + price + cashback, but **no free-shipping ("Kargo Bedava"), campaign-label, or bestseller badge**. Trendyol search cards are known to carry these (general knowledge; **not fetched — 403**).
Gap: missing merch/trust badges on result cards.
Severity rationale: badges are part of Trendyol's at-a-glance card recognition; MED because they affect scannability, but PROBABLE because the Trendyol side wasn't fetched.
Recommendation: confirm during the build PR's discovery (screenshots or re-fetch), then `P5-card-badges`. **Note backend dependency:** free-shipping/campaign flags must come from the catalog API; UI-only until then.
**Outcome (NOT-ACTIONABLE — `chore/step5-low-batch`):** backend-gated — `ProductSummary` exposes no `free_shipping`/`campaign`/`badge` field. P-028 added the `free_shipping` *column* but not the response field, and it's unpopulated. A badge UI is pointless until the API exposes the flags + has data. (Severity re-confirmed **MED**, not LOW — this batch's prompt mislabeled it.) No code change.
**Outcome 2 (✅ BACKEND-UNBLOCKED, partial — `feat/productsummary-enrich`):** `ProductSummary` now emits `free_shipping` (the "Kargo Bedava" badge); `discount_pct` + `flash_price_minor` were already emitted (discount + flash badges). So every P-009 badge **except bestseller** (= P-029, cross-schema popularity) is now backend-ready; frontend wiring is a small follow-up. (free_shipping data is unpopulated — the badge renders once sellers flag products.)
**✅ RESOLVED (frontend — `feat/wire-card-badges`):** the card renders a "Ücretsiz Kargo" badge (top-left image overlay) when `product.freeShipping`; the discount-% badge (`DiscountPill`, #78) already renders. So the **free-shipping + discount** card badges are live; **bestseller** remains the only deferred badge (→ P-029). (free_shipping data is seller-populated — the badge shows once products are flagged.)

### P-010 — Filters / sort UI is built (parity likely; detail PROBABLE)
**Status: INTERACTION | Severity: LOW | Confidence: CONFIRMED (Mopro) / PROBABLE (gap)**
Evidence: `plp/widgets/filter_panel.dart` (377 LOC, desktop sidebar), `filter_sheet.dart` (239, mobile sheet), `plp_filter_chips.dart` (active-filter chips), `sort_sheet.dart` (sort options). Trendyol's exact filter dimensions/order unverified (403).
**Verdict:** Mopro has the Trendyol filter/sort *patterns* (sidebar on web, sheet on mobile, chips). Dimension-level parity is PROBABLE → confirm in a discovery pass. No NOW action.

---

## §3.4 Category browse findings
Mopro: `catalog/screens/category_products_screen.dart` (282) reuses `CatalogShell` (consistent with search — good). Goldens `catalog/plp/goldens`. Trendyol category pages 403. **No CONFIRMED gap;** consistency with search is a positive. Detail PROBABLE → folded into P-009/P-010 discovery.

---

## §3.5 PDP findings

Mopro PDP is the richest surface: `product_detail_screen.dart` (950 LOC) + `pdp_image_gallery.dart` (140) + `pdp/pdp_image_pager.dart` (200) + `pdp/pdp_price_block.dart` (89) + `pdp/pdp_sticky_cta.dart` (65) + reviews tab (§3.6) + Q&A tab (§3.7) + recommendations (`recs_pdp_similar_*` goldens). Goldens: `catalog/pdp/goldens`. **Trendyol PDP not fetchable (403-class).**
CONFIRMED PDP structure (`product_detail_screen.dart`, read): a **4-tab** `TabBar` — Description / Specs / Reviews / Q&A (`product.{description,specs,reviews,qa}_tab`, line 213-219) — plus a **`_StockPill`** stock indicator (line 458), a **`PdpSellerCard`** seller-info block that deep-links to the seller storefront (`/sellers/{slug}`, hidden when the slug is null — line 471-476), and a `_SimilarProductsRail` (line 389). So every §3.5 sub-element the prompt enumerates (gallery, variants, price, buy box, description/specs, reviews, Q&A, recommendations, seller info, stock) is present.

### P-027 — PDP buy box EXISTS and is sticky (corrects the prompt's sample assumption)
**Status: INTERACTION | Severity: — | Confidence: CONFIRMED → VERIFIED-COMPLETE**
Evidence: `pdp/pdp_sticky_cta.dart:11-65` — mobile sticky bottom CTA: selected-variant price + full-width "Sepete Ekle" (`product.add_to_cart.tr()`), disabled until a variant is selected and during cart mutation, 52px height (touch target ✓), `cs.primary` (theme-aware ✓). `pdp_price_block.dart:32-88` — brand-orange current price, strikethrough original + discount-% pill, **`lowest_30d` hint slot**.
**Verdict:** VERIFIED-COMPLETE for sticky positioning + buy-box structure. The prompt's illustrative "P-007 — buy box lacks sticky positioning" is **factually wrong on this branch** (documented per §2.5).

### P-007 — PDP buy box lacks a delivery-estimate
**Status: ✅ RESOLVED (via P-034) | Severity: MED | Confidence: CONFIRMED (Mopro) / PROBABLE (Trendyol)**
**Resolution:** the PDP buy box now renders a `PdpDeliveryInfo` row ("{min}-{max} iş gününde kargoda", hedged "tahmini" for fallback estimates, optional "{city} çıkışlı") backed by the P-034 `delivery_eta` field on `GET /products/{id}`. Shipped end-to-end with the shipping-ETA infra below. Evidence: `docs/internal/p034-shipping-eta-architecture.md`; `mobile/lib/features/catalog/widgets/pdp/pdp_delivery_info.dart`. The original discovery is retained below for the record.

_Original (deferred) state:_
**Status was: ⏸️ DEFERRED (blocked by shipping-ETA infra → P-034) | Severity: MED | Confidence: CONFIRMED (Mopro) / PROBABLE (Trendyol)**
Evidence: `pdp_sticky_cta.dart` (read) + `pdp_price_block.dart` (read) render price + CTA + discount + lowest-30d, but **no delivery-date / "Yarın kargoda" estimate**. Trendyol prominently shows an estimated-delivery line in/near the buy box (general knowledge; PDP not fetched — the homepage meta did advertise "same-day delivery"). 
Gap: no delivery-ETA affordance on PDP.
Severity rationale: delivery ETA is conversion-relevant and a recognizable Trendyol element; MED. PROBABLE on the Trendyol side (not fetched).
Recommendation: `P5-pdp-delivery-eta` — add a delivery-estimate row. **Backend dependency:** ETA must come from shipping/catalog API; this is partly out of UI scope (the slot can land with a placeholder, data SOON).
**Discovery (`feat/delivery-eta`, Outcome C):** no pre-purchase ETA infrastructure exists. `internal/shipping/` is a carrier-adapter layer for *real* shipments; `CalculateRate.EstimatedDays` is a **live carrier call** needing a full `ShipmentInput` (origin/dest/package) — checkout-time, not PDP. The foundational inputs are absent: **no seller dispatch origin** (no warehouse/city on the seller model — onboarding territory) and **no zone/transit-days model**; only the user destination exists (`identity.Address` city/district; guests have none), and there's no PDP delivery slot. A hardcoded static line is rejected (§9 SLA-promise + misleading, worse than nothing). **Decision: discovery-only — PDP unchanged.** Filed **P-034**. Evidence: `docs/internal/p007-delivery-eta.md`.

### P-034 — no pre-purchase shipping-ETA infrastructure (blocks PDP delivery-ETA) (carved from P-007)
**Status: ✅ SUPERSEDED (carve collapsed — built directly in the P-007 PR) | Severity: MED | Confidence: CONFIRMED | Type: backend (shipping + seller)**
P-034 was carved from P-007's Outcome-C deferral as a standalone enabler. On the second pass it was built **directly inside the P-007 PR** (`feat/delivery-eta`) rather than as a separate deliverable, so it never becomes its own roadmap item — it is **superseded** by, and folded into, that PR. The infra below all shipped there; P-007 is RESOLVED end-to-end.
Evidence (original): a cheap delivery estimate = `transit_days(originZone, destZone)`, but there was **no seller dispatch origin** (absent on the seller model / `0078_sellers`) and **no zone/transit-days lookup** anywhere; `CalculateRate` is a live per-call carrier API needing a full `ShipmentInput`, unfit for PDP. User destination (`identity.Address` city/district) exists; guests don't.
**Resolution (`feat/delivery-eta`):** (1) migration `0084` adds seller `dispatch_city` (seeded); (2) migration `0085` seeds `ref_schema.shipping_zones` + `transit_days` + `transit_default` (7 coarse TR zones, 49-pair matrix); (3) `shipping.EstimateETA(market, originCity, destCity?)` — a joined `ref_schema` lookup, **no carrier call**, guest → conservative national fallback (`confident=false`); (4) `delivery_eta` on `GET /products/{id}` (+`dest_city` param) + the `PdpDeliveryInfo` widget + i18n. Spec/clients regenerated; tests `-race` clean; boundaries OK. Closes **P-007**. `CalculateRate.EstimatedDays` remains available for a future *checkout* estimate. Doc: `docs/internal/p034-shipping-eta-architecture.md`.

### P-008b — PDP discount + lowest-30d UI present but data-dark (backend, OUT OF SCOPE)
**Status: FUNCTIONAL | Severity: — | Confidence: CONFIRMED**
Evidence: `pdp_price_block.dart:14-31` — `originalPriceMinor` and `lowestIn30DaysMinor` are nullable "because the catalog API does not expose them yet; when null the corresponding row is simply omitted." Same on `ProductCard` (§3.5). So the **discount + lowest-30d UI exists but never renders** (no data).
**Verdict:** This is a **backend-data gap, not a UI parity gap** → out of Step-5 scope (prompt §1.2 "Backend changes … out of scope"). Logged so the parity PRs don't re-build existing UI; flag for a catalog-API follow-up.
**Outcome (split — `feat/productsummary-enrich`):** the **discount** portion is ✅ done — `original_price_minor` (variants, 0065) + a handler-computed `discount_pct` are already emitted on `ProductSummary`; the strikethrough + %-badge render once a product has an `original_price_minor`. The **lowest-30d** portion is carved to **P-030** (HIGH, compliance — no price-history infrastructure exists).

### P-015 — PDP variant swatches / size-guide fidelity (PROBABLE)
**Status: VISUAL/INTERACTION | Severity: LOW | Confidence: PROBABLE**
Evidence: Mopro PDP has variant selection (in `product_detail_screen.dart`); swatch styling vs Trendyol (color chips, size-guide link, out-of-stock treatment) unverified (PDP 403). → confirm in discovery; no NOW action.
**Outcome (✅ FIXED — `chore/step5-low-batch`):** the **out-of-stock treatment** was a confirmable Mopro-side bug — `PdpVariantSelector` let you select stock==0 variants into the buy box. Fixed: OOS chips render struck-through + disabled (`Variant.stock`; +1 widget test; no golden impact — fixtures are all in-stock). The broader swatch/size-guide-link fidelity stays PROBABLE (Trendyol 403) — not actioned.

---

## §3.6 Reviews findings

### P-016 — Reviews surface is built end-to-end
**Status: STRUCTURAL | Severity: — | Confidence: CONFIRMED (Mopro) → VERIFIED-COMPLETE (Mopro side)**
Evidence: `catalog/pdp/reviews/` — `pdp_reviews_tab.dart` (243), `rating_distribution_histogram.dart` (155), `review_row.dart` (191), `review_form_content.dart` (211), `reviews_provider.dart` (280), `review_write_provider.dart` (298). Goldens: `reviews/goldens` (`pdp_reviews_tab`, `review_form`), plus `account/goldens/my_reviews_{populated,empty}`. Review submission is auth-gated via `requireAuth` (`review_row.dart:26`, `review_submission.dart:24` — see §4.4).
**Verdict:** VERIFIED-COMPLETE on the Mopro side (list + rating histogram + write flow + verified gating). Trendyol pixel-detail PROBABLE (PDP 403). No NOW action.

---

## §3.7 Q&A findings

### P-017 — Q&A surface is built end-to-end
**Status: STRUCTURAL | Severity: — | Confidence: CONFIRMED (Mopro) → VERIFIED-COMPLETE (Mopro side)**
Evidence: `catalog/pdp/qa/` — `pdp_qa_tab.dart` (202), `question_row.dart` (90), `answer_row.dart` (71), `qa_form_content.dart` (179), `qa_provider.dart` (394), `qa_submission.dart` (gated via `requireAuth`, line 16/46), `screens/question_detail_screen.dart` (158). Goldens: `qa/goldens` (`pdp_qa_tab`, `qa_widgets`, `qa_form`), `account/goldens/my_questions_populated`.
**Verdict:** VERIFIED-COMPLETE on the Mopro side. No NOW action.

---

## §3.8 Cart findings

Mopro cart: `features/cart/` (15 files, 1372 LOC) — `cart_screen.dart` (215), `cart_line_card.dart` (149), `order_summary_card.dart` (150), `cart_totals_summary.dart` (197), `empty_cart.dart` (48), **`guest_cart_provider.dart` (117)**. Golden: `cart/widgets/goldens/cart_line_card`. Trendyol cart is login-gated → PROBABLE.

CONFIRMED cart-totals internals (`cart_totals_summary.dart`, read): grand total (`₺`, `tr_TR`, `cart.kdv_included` label), item count, **a `_CashbackSummaryBox`** (monthly Mopro Coin + `cart.cashback_perpetual` note — D-001), and limit warning chips (`cart.warning_{total,item}_limit`), then the proceed-to-checkout `FilledButton`.

### P-011 — Cart lacks promo-code entry, cross-sell suggestions, and saved-for-later
**Status: FUNCTIONAL/CONTENT | Severity: LOW | Confidence: CONFIRMED (Mopro) / PROBABLE (Trendyol)**
Evidence (corrects an earlier draft of this finding): `cart_totals_summary.dart` (read in full) has **no promo-code field**, and the cart feature (15 files, listed) has **no cart-page suggestion rail and no saved-for-later** widget. Trendyol cart carries a coupon entry + "Bunlara da Göz At" suggestions + save-for-later (general knowledge; login-gated, not fetched).
Gap: (a) no promo/coupon entry, (b) no cart cross-sell, (c) no save-for-later.
Severity: LOW. **Divergence caveat:** promo/coupon absence may be intentional — Mopro's discount mechanic is **perpetual cashback**, not coupons (the `_CashbackSummaryBox` occupies the slot a coupon field would). Confirm product intent before treating (a) as a gap; (b)/(c) are additive.
Recommendation: `P5-cart-suggestions` (LATER) — reuse `ProductListRail` for (b); (a)/(c) only if product wants coupons/save-for-later. Confirm Trendyol side first.
**Positive:** guest cart is preserved (`guest_cart_provider.dart`) — browse + add without auth; gate only at checkout (§4.4). Matches the original ask exactly.
**Outcome (CORRECTED — `chore/step5-low-batch`):** claim (a) "no promo-code field" is **wrong on this branch**. The active cart totals widget is `OrderSummaryCard` (`cart_screen.dart:120`), which **has** a coupon input (`order_summary_card.dart:97-109`, an inert placeholder — "coupon backend not wired"). The audit cited `cart_totals_summary.dart`, an **orphaned** widget the cart no longer mounts. (b) cross-sell + (c) saved-for-later remain absent (PARK/additive — unchanged). The promo *mechanic* is still arguably an intentional cashback divergence; the point is the field exists.

---

## §3.9 Checkout findings

Mopro checkout: `features/checkout/` (13 files, 1738 LOC) — `checkout_stepper.dart` (103), `checkout_address_screen.dart` (223), `checkout_payment_screen.dart` (306), `checkout_review_screen.dart` (331), `checkout_redirect_screen.dart` (180), `checkout_result_screen.dart` (173), `sipay_webview_screen.dart` (167, 3-DS). **No goldens** (coverage gap — see P-019). Trendyol checkout login-gated → PROBABLE.

CONFIRMED checkout internals (`checkout_address_screen.dart`, read): a saved-address list (`addressesProvider`) of `_SelectableAddressCard`s with a **default badge** (`address.isDefault → address.default`), an **empty state** (`address.empty` + add-address CTA), and a continue button gated on `selectedAddress != null` (line 94) — matches Trendyol's saved+default address selection. (Delivery-method options + installments not confirmed; installments are likely an intentional divergence — Mopro is cashback, not BNPL.)

### P-012 — Checkout flow shape: multi-screen stepper vs Trendyol single-page
**Status: INTERACTION | Severity: LOW | Confidence: PROBABLE**
Evidence: Mopro uses a multi-screen linear stepper (address → payment → review → 3-DS redirect → result), with `checkout_stepper.dart` rendering progress. Trendyol web leans single-page collapse-expand (general knowledge; not fetched).
Gap: flow-shape difference (stepper vs single-page). 
Severity: LOW — both are valid e-commerce patterns; Mopro's stepper is coherent and the 3-DS/SAQ-A constraints (sipay) justify screen separation. PROBABLE.
Recommendation: do **not** restructure without confirming Trendyol's current pattern + a UX rationale; PARK unless discovery shows a real friction gap. The auth gate at checkout entry (`cart_screen.dart:80 → requireAuth`) is the original ask's transition point and is correctly an adaptive prompt (§4.4), not a hard page-redirect — good.
**Outcome (NOT-ACTIONABLE — `chore/step5-low-batch`):** documented design. `checkout/widgets/checkout_stepper.dart` renders a coherent multi-screen stepper; the 3-DS/SAQ-A (sipay) constraints justify screen separation. Restructuring a working stepper on taste (against a 403'd reference) is unwarranted. No code change.

---

## §3.10 Account / Profile findings

### P-018 — Account surfaces are built
**Status: STRUCTURAL | Severity: — | Confidence: CONFIRMED (Mopro) → VERIFIED-COMPLETE (Mopro side)**
Evidence: `features/account/` (16 files, 3469 LOC). Goldens: `account/goldens/account_profile_{1024,1440}`, `account_security_{1024,1440}_{light,dark}`, `account_welcome_{guest,}_*` (the guest welcome state — confirms guest browsing of the account tab), `browsing_history_*`, `my_reviews_*`, `my_questions_*`.
**Verdict:** VERIFIED-COMPLETE on the Mopro side (profile + security/MFA + browsing history + my-reviews/my-questions + guest welcome). See P-014 for hardcoded strings in `security_screen.dart`.

---

## §3.11 Orders / Returns findings

### P-019 — Orders/Returns/Refund built with strong golden coverage
**Status: STRUCTURAL | Severity: — | Confidence: CONFIRMED (Mopro) → VERIFIED-COMPLETE (Mopro side)**
Evidence: `features/order/` (21 files, 3275 LOC). Goldens: `order/goldens/returns_list_{populated,empty}_1440_light`, `refund_card_{issued,pending,processing,failed}_light` (all 4 refund states), `timeline_{return_requested,refund_issued}_light`. Seller side: `seller/goldens/seller_returns_inbox`, `seller_return_detail_actions`.
**Verdict:** VERIFIED-COMPLETE on the Mopro side — return initiation, status timeline, and refund-state cards all rendered + golden-locked. Trendyol detail PROBABLE (login-gated).
**Coverage note:** `features/orders` (plural) is an **empty directory** alongside the real `features/order` (singular) — a drive-by cleanup nit (not a parity finding); flag for a Step-1-style cleanup sweep.

---

## §3.12 Favorites findings

### P-013 — Favorites is a flat list (no collections/folders)
**Status: STRUCTURAL/FUNCTIONAL | Severity: LOW | Confidence: CONFIRMED (Mopro) / PROBABLE (Trendyol)**
Evidence: `features/favorites/` is **2 files, 220 LOC** (`favorites_screen.dart` + `favorites_provider.dart`) — a flat grid, no collection/folder model. Golden `favorites/goldens`. Trendyol favorites supports named lists/collections (general knowledge; login-gated, not fetched).
Gap: no favorite-list organization (folders/collections/sharing).
Severity: LOW. **Possibly PARK** — collections may be outside Mopro's near-term product scope (a niche-marketplace decision); confirm product intent before building.
Recommendation: `P5-favorite-collections` (LATER/PARK). The add/remove interaction itself is at parity — heart top-right on cards (`product_card.dart:88-98`), guest-local + server-sync-on-auth.
**Outcome (NOT-ACTIONABLE — `chore/step5-low-batch`):** PARK — collections/folders are a product-intent decision outside the near-term scope; the flat list + add/remove are at parity. No code change.

---

## §3.13 Auth flow findings

Mopro: `features/auth/` (15 files, 1797 LOC) — login (phone/OTP), OTP screen, profile completion, email verify. Golden `auth/goldens/auth_card`. The dev-OTP-bypass is injected (`identity.WithDevOTPBypass`, A4-3/#76) and **off in production** (panics if on in prod) — so it is correctly hidden from this surface in prod (prompt §3.13). Trendyol login page not fetched → PROBABLE.

### P-014 — Hardcoded Turkish strings bypass `.tr()` (auth + checkout + account + PDP + favorites)
**✅ RESOLVED — closed across 7 phased PRs (#79→#83).** Every user-facing hardcoded Turkish string in
`mobile/lib` is now routed through `.tr()` (verified: 0 diacritic-detectable + 0 common ASCII-only TR
remain in UI sinks; ~250+ strings localized; tr-TR master + en-US, 0 TRANSLATION_NEEDED). Intentional
inline kept: language self-names (`'Türkçe'`/`'العربية'`), brand (`'Mopro · '`), code/mask placeholders.
**Second discovery-shift (the audit undercounted ~3×):** the
all-sinks re-grep on `feat/i18n-hardcoded-sweep` found **~155 hardcoded TR strings across 27 files** — not
the ~55 the `Text()`-scoped audit estimated. Whole screens are unlocalized (security_screen 29, account_screen
21, sign_up 15, sipay_error_map 13, sign_in 12, email_verify 10, mfa 9, …). A full sweep is ~1500–2000 LOC /
27 files — a multi-PR effort.
- **Phase 1 ✅ (`feat/i18n-hardcoded-sweep`):** `t()`→`withBrand` + app_router title localization (44 `router_title.*`).
- **Phase 2c ✅ (`feat/i18n-sweep-2abc`):** sipay error map → `payment.error.sipay.*` (12 keys, dynamic prefix).
- **Phase 2a ✅ (`feat/i18n-sweep-2abc`):** auth — sign_up + sign_in + auth_layout (~46 strings; `auth.*`/`auth.sign_up.*`/`auth.sign_in.*`/`auth.layout.*`).
- **Phase 2b ✅ (`feat/i18n-sweep-2b-account`):** account area — security_screen (40 `security.*` keys; 2 namedArgs interpolations; const dialogs/snackbars) + account_screen (17 `account.*`; theme dedup, softGated prompts). Both full-read swept; `account_security` goldens regen Turkish→keys.
- **Phase 2d ✅ (`feat/i18n-sweep-2d`):** email_verify + mfa_challenge + forgot_password + auth_widgets (strength rules + `veya`) + hero_slides (marketing) — ~34 keys (`auth.*`/`auth.email_verify.*`/`auth.mfa.*`/`auth.forgot.*`/`auth.password_rule.*`/`marketing.hero.*`). RichText prefix/suffix + `const heroSlides`→function. profile_screen was VERIFIED-COMPLETE (locale self-names). **0 golden impact** — `HeroCarousel`/`hero_slides` is an *unadopted* widget (no consumer; home mounts `MoodStoriesStrip`); localized for completeness + future adoption (new cleanup finding filed). **[✅ REMOVED — `chore/step5-low-batch`: re-verified zero consumers (home mounts `MoodStoriesStrip` → `_BannerCarousel`); deleted `hero_carousel.dart` + `hero_slides.dart` + the `marketing.hero.*` keys.]**
- **Phase 2e + 2f ✅ (`feat/i18n-sweep-2ef`, #83) — CLOSES P-014:** cart/checkout were already mostly localized, so the remainder was small (~32 strings): checkout_redirect (const-list→build-time), cart softgate, web_header (`auth.login` reuse), header_search_bar, theme_toggle, mega_menu (×2), favorites, product_detail, search_screen (`router_title` reuse), help_article, app_router (`account.title` reuse), + home search-hints/rail/trending fallbacks. 8 goldens regen (web_header ×3, home ×3, favorites_empty ×2). web_header_test + mega_menu_keyboard_test → key assertions (#79 pattern).
- **Third discovery-shift:** the diacritic grep undercounts ~2× (misses TR strings w/o special chars — "Ad", "Parola", "Giriş"). **True P-014 scope ≈ 250–300 strings**, not 155. Future phases counted by full-file read, not diacritic grep.
The 11-string list below was a `Text()`-scoped floor (correctly flagged as a floor at the time).
**Status: CONTENT | Severity: LOW | Confidence: CONFIRMED**
Evidence (grep, this branch — 11 literal Turkish UI strings not routed through `.tr()`):
- `features/auth/email_verify_screen.dart:64` `'Doğrulama kodu tekrar gönderildi.'`, `:162` `'Kodu tekrar gönder'`
- `features/checkout/presentation/checkout_redirect_screen.dart:141` `'Siparişlerime Git'`, `:146` `'Alışverişe Devam Et'`
- `features/account/security_screen.dart:109,143,196` (MFA snackbars), `:125` `'Vazgeç'`, `:503` `'Telefon numarasını değiştir'`
- `features/catalog/screens/product_detail_screen.dart:57` `'Ürün bulunamadı.'`
- `features/favorites/favorites_screen.dart:174` `'Keşfet'`
**This count is a floor:** the grep was scoped to `Text('…')`; literals in other sinks slip through — e.g. `catalog/screens/search_screen.dart:43` sets a non-localized browser-tab label `'Mopro · "$query" araması'` via `ApplicationSwitcherDescription`. The sweep PR should grep all string sinks, not just `Text(`.
Gap: these break for any non-TR locale and bypass the Step-3 i18n completeness gate (which checks key *usage*, not literal bypass).
Severity: LOW (mostly snackbars/buttons), but it's a clean, fully-CONFIRMED, zero-dependency fix.
Recommendation: `P5-i18n-hardcoded-sweep` — move all 11 to `tr-TR`/`en-US` keys. **Tooling-adjacent:** consider a follow-up lint (Step-3 family) that flags user-facing string literals containing Turkish characters — the existing analyzer can't catch these. (Cross-link: ROADMAP idempotency-surface-analyzer tail.)

---

## §3.14 Notifications findings

### P-021 — Notifications built (inbox + preferences)
**Status: STRUCTURAL | Severity: — | Confidence: CONFIRMED (Mopro) → VERIFIED-COMPLETE (Mopro side)**
Evidence: `features/notifications/` (8 files, 955 LOC). Goldens: `notifications/goldens/notification_rows_light`, `notifications_list_{populated,empty}_1440_{light,dark}`, `notification_preferences_1440_light`.
**Verdict:** VERIFIED-COMPLETE on the Mopro side (in-app inbox list + read/unread rows + preferences screen). Push opt-in timing PROBABLE. No NOW action.

---

## §3.15 Help / Contact findings

### P-022 — Help surface built
**Status: STRUCTURAL | Severity: — | Confidence: CONFIRMED (Mopro)**
Evidence: `features/help/` (10 files, 953 LOC). Golden `help/goldens`.
**Verdict:** Built; Trendyol help detail PROBABLE (not fetched). No NOW action.

---

## §3.16 Empty / error / loading states findings

### P-023 — Shared empty/error/loading primitives exist and are reused
**Status: CONTENT/VISUAL | Severity: — | Confidence: CONFIRMED → VERIFIED-COMPLETE**
Evidence: `core/widgets/empty_state.dart`, `core/widgets/error_banner.dart`, `core/widgets/loading_spinner.dart`, `widgets/skeleton_box.dart`; surface-level skeletons (`SkeletonProductCard` in `product_card.dart:249-290`, `_FlashSkeleton` in `flash_deals_rail.dart:168`); empty states golden-locked (`order/goldens/returns_list_empty`, `notifications_list_empty`, `account/my_reviews_empty`, `cart/empty_cart.dart`).
**Verdict:** VERIFIED-COMPLETE — the dimension prompts most often warn is skimped is actually systematized here (shared widgets + per-surface skeletons + empty goldens).

---

## §3.17 Accessibility findings

### P-020 — Dark-mode primary-on-surface contrast fails AA (already tracked by the contrast gate)
**✅ RESOLVED — P5-2 (`feat/parity-card-pdp-polish`).** `primaryDark` nudged `#E36925` → `#E97230`; `verify-contrast` now measures **4.66:1** on `surfaceDark` (was 4.26:1), and the pair's `backlog` exemption is removed (hard Pass). Light-mode `primaryLight` untouched. 35 dark-mode goldens re-baselined on Linux.
**Status: VISUAL/a11y | Severity: MED | Confidence: CONFIRMED**
Evidence: `make verify` → `verify-contrast` (`mobile/test/design/contrast_test.dart`) prints, on this branch:
`| #E36925 on surfaceDark (text) | 4.26:1 | 4.5:1 | FAIL (Backlog) |`.
So `MoproTokens.primaryDark` (#E36925) text on `surfaceDark` (#302A24) is **4.26:1 < 4.5:1 AA** — a known, gate-tracked backlog item.
Gap: one dark-mode token pair below AA for normal text.
Severity: MED (a11y; bounded to one pair, dark mode).
Recommendation: `P5-darkmode-contrast` (NOW, tiny) — nudge `primaryDark` lighter or use it only for ≥18px/bold (large-text AA is 3:1, which it passes), then flip the contrast row from "Backlog" to "Pass". Pure token change + gate flip.
**Positive (VERIFIED-COMPLETE elsewhere):** touch targets meet 44×44 (theme `filledButton`/`outlinedButton` `minimumSize: (64,48)`, sticky CTA 52px); contrast is *gated* (`verify-contrast`); `design/widgets/skip_to_content_link.dart` + focus goldens (`skip_to_content_link_focused_1024_*`) show keyboard/skip-link support on web. Screen-reader label coverage on icon-only buttons is PROBABLE (not exhaustively audited) → discovery item.

---

## §3.18 Responsive behavior findings

### P-024 — Responsive system is systematized and golden-locked at 4 breakpoints
**Status: STRUCTURAL | Severity: — | Confidence: CONFIRMED → VERIFIED-COMPLETE**
Evidence: `design/responsive/` — `breakpoints.dart`, `breakpoint_resolver.dart` (`context.isMobile/isTablet/isDesktop`), `adaptive_value.dart`, `responsive_builder.dart`, `centered_content_column.dart`, `responsive_image_url.dart`, `hover_region.dart`/`pointer_kind.dart` (web hover vs touch). Goldens exist at **375 (mobile), 768 (tablet), 1024, 1440 (desktop)** across home/account/seller/shell suites. Flash-deals + product grids reflow by breakpoint (read in §3.1).
**Verdict:** VERIFIED-COMPLETE for mobile-portrait/tablet/desktop. **Mobile-landscape** is not explicitly golden-tested (prompt §3.18 flags it as "often broken") → UNKNOWN-adjacent discovery item, not a CONFIRMED gap.

---

## §4.1 Design tokens findings

### P-001 — Design-token system is complete and cross-platform (the would-be HIGH, resolved)
**Status: VISUAL/STRUCTURAL | Severity: — | Confidence: CONFIRMED → VERIFIED-COMPLETE**
Evidence: `mobile/lib/design/tokens.dart` (83 LOC) — full palette (`primaryLight/Dark`, surfaces, foreground, `mutedFg`, semantic `destructive/success/warning`, dedicated `ratingStar` gold), an **8-pt spacing grid** (`space2…space48`), a **radius scale** (`radiusSm…radius2xl`, `radiusFull`); comment: "derived from globals.css OKLCH tokens" → **web (`globals.css`) and mobile share a token origin** (cross-platform consistency). `theme.dart` (287 LOC) builds full M3 component themes from tokens (card, appBar, bottomNav, navigationBar, filled/outlined/text buttons, input, chip, divider, snackBar) + Inter type scale (display→label).
**Verdict:** **VERIFIED-COMPLETE.** The prompt (§13) anticipated exactly this: "If discovery during P-001 reveals tokens are already systematized … P-001 closes as VERIFIED-COMPLETE." It does. **No P-001 PR is needed.**

### P-005 — Token-adherence drift on `ProductCard` (a few hardcoded values bypass the system)
**✅ RESOLVED — P5-1 (`feat/parity-card-pdp-polish`).** Card price → `cs.primary` (theme-aware; was the hardcoded light-mode orange on the dark card). The discount hex is gone (folded into P-006's shared pill). The two heart colours on the white chip are kept by design (theme-independent — see `docs/internal/p5-card-pdp-polish.md`). No new token added.
**Status: VISUAL | Severity: LOW | Confidence: CONFIRMED**
Evidence (`product_card.dart`, read): line 174 price uses `MoproTokens.primaryLight` (the **hardcoded light-mode** orange) instead of `cs.primary` → in **dark mode the price stays #CA4E00 instead of #E36925**; line 154 discount badge uses one-off `Color(0xFFE53935)` (not a token); line 220 inactive heart uses `Color(0xFF888888)` (not a token). (By contrast `pdp_price_block.dart`/`pdp_sticky_cta.dart` correctly use `cs.primary`.)
Gap: the token *system* is complete (P-001) but a few card widgets bypass it → dark-mode/maintenance drift.
Severity: LOW (cosmetic, dark-mode card price).
Recommendation: part of `P5-1` — swap to `cs.primary` / add a `MoproTokens.discountBadge` token; lock with a dark-mode card golden.

### P-006 — Discount-pill color inconsistent within Mopro (card red vs PDP orange)
**✅ RESOLVED — P5-1 (`feat/parity-card-pdp-polish`).** New shared `design/widgets/discount_pill.dart` on `cs.error` (the design system's designated *destructive*/discount token), used by both card + PDP. Resolves the card's one-off red hex (P-005) and the PDP's brand-orange in one place. No new token.
**Status: VISUAL | Severity: LOW | Confidence: CONFIRMED**
Evidence: `product_card.dart:154` discount pill is **red** (`0xFFE53935`); `pdp_price_block.dart:51-56` discount pill is **brand-orange** (`cs.primary`). Same concept, two colors across surfaces. (Trendyol uses green discount pills — general knowledge; either color is a divergence from Trendyol, but the **intra-Mopro inconsistency** is the CONFIRMED finding.)
Severity: LOW.
Recommendation: part of `P5-1` — pick one discount-pill token and apply on both card + PDP.

---

## §4.2 Navigation patterns findings
`go_router` route structure is comprehensive (web mirrors it: `web/app/[locale]/...` has products/[id]/[slug], search, cart, checkout(+redirect), orders/[id], account/{security,cards,favorites,profile,addresses,cashback,orders}, categories/[slug], login). Deep-linking + back-stack PROBABLE (not exercised in this audit). No CONFIRMED gap. Tab scroll-restoration UNKNOWN → discovery item.

## §4.3 Cross-cutting interactions findings
- **Cart badge** — live (`web_header.dart:41/91` `cartCountProvider`). CONFIRMED ✓.
- **Favorites heart** — present on cards (`product_card.dart:88`), guest-local. CONFIRMED ✓.
- **Search-everywhere** — persistent web pill + mobile nav-adjacent. CONFIRMED ✓ (§3.2).
- **Pull-to-refresh** — home uses a `RefreshIndicator`/invalidate pattern (`home_screen.dart:64`); per-surface coverage PROBABLE. No CONFIRMED gap.

## §4.4 Auth-gating consistency findings

### P-025 — Auth gate is a single, consistent, guest-preserving helper (the original ask's core constraint — DONE)
**Status: FUNCTIONAL | Severity: — | Confidence: CONFIRMED → VERIFIED-COMPLETE**
Evidence: `core/widgets/login_required_sheet.dart` exports `requireAuth(context, ref, {onAuthed, reason})` (line 48-60): if `AuthAuthenticated` runs `onAuthed` immediately, else shows an **adaptive** prompt — bottom sheet `<600`, centered `AuthCard` dialog `>=600` (line 12-44) — with a **resume callback** (`onResume`/`onAuthed`) so post-login returns to the intended action. Every personal action routes through it:
- cart checkout — `cart/presentation/cart_screen.dart:80 _checkout → requireAuth`
- review submit — `pdp/reviews/review_row.dart:26`, `review_submission.dart:24`
- Q&A submit — `pdp/qa/qa_submission.dart:16,46`
- account guest state — `account/account_screen.dart:733 showLoginRequiredSheet` (presenting, not action-gating)
Guests are **not** blocked from browsing, toggling favorites (local, server-sync on auth — `product_card.dart:94-96`), or building a cart (`guest_cart_provider.dart`). Golden: `core/widgets/goldens/login_required_sheet_{light,dark}.png`.
**Verdict:** **VERIFIED-COMPLETE.** This is the prompt's "most product-critical cross-cutting concern" (§4.4) and it is a model implementation — consistent widget, consistent placement, resume-redirect present, guest browsing preserved. **No gap.**

## §4.5 Localization findings
Covered by **P-014** (11 hardcoded strings bypass `.tr()`). The Step-3 i18n gate (0 missing / 0 dead keys) holds for *keyed* strings; the gap is *literal bypass*, which that gate doesn't catch. easy_localization is wired app-wide; tr-TR/en-US are the live locales.

---

## §5 Verified-complete surfaces

Each closed with the evidence above — **do not rebuild these; polish only per §6.**

1. **Design tokens** (P-001) — `tokens.dart` + `theme.dart`, web/mobile shared OKLCH origin.
2. **Auth-gate / guest browsing** (P-025) — single `requireAuth`, resume callback, guest-preserving. *The original ask's core constraint.*
3. **Global navigation** (P-002) — 5-tab bottom nav + web header (logo/search/fav/cart-badge/account/megamenu); goldens.
4. **Home composition** (P-003) — every Trendyol home element + Mopro extras; goldens at 375/768/1440.
5. **Flash deals** (P-008) — live HH:MM:SS countdown + responsive; goldens.
6. **Product card** (P-004 base) — Trendyol-shaped (image/heart/brand/title/rating/discount/price/cashback) + skeleton.
7. **PDP structure** (P-027) — gallery/pager, variants, price block, **sticky CTA**, reviews + Q&A tabs, similar-products rail; goldens.
8. **Search/PLP filters + sort** (P-010) — filter panel (web) / sheet (mobile) / chips + sort sheet; goldens.
9. **Reviews** (P-016) & **Q&A** (P-017) — list + write flows, gated; goldens.
10. **Orders/Returns/Refund** (P-019) — timeline + 4 refund states + returns list; goldens (+ seller side).
11. **Notifications** (P-021), **Account** (P-018), **Empty/loading/error** (P-023), **Responsive** (P-024) — all built + golden-locked.

---

## §6 Recommended parity-PR sequence

The mature-app reality: **no foundational HIGH PR is needed** (tokens + auth-gate are done). The sequence is fidelity polish + data wiring + PROBABLE-confirmation. Each PR follows the arc shape (discovery → build → tests/goldens → docs closure) and references its `P-ID`.

### NOW (fully CONFIRMED, zero dependency, low risk)

**P5-1 — Card + PDP fidelity polish.** ✅ **DONE** (`feat/parity-card-pdp-polish`). Closed **P-005** (card price → `cs.primary`) + **P-006** (shared `DiscountPill` on `cs.error`). **P-014 SPLIT out** — discovery showed it's a ~55-string cross-app sweep + a `t()` helper refactor, not card/PDP polish → `feat/i18n-hardcoded-sweep`.
- Size: ~250–350 Flutter LOC (widget edits + tr-TR/en-US keys).
- Risk: **LOW** (pure UI, no auth, no API).
- Prereqs: none (design tokens already exist — P-001).
- Goldens: **regenerate** card + PDP price-block goldens, add a **dark-mode** card golden (CI Linux baseline).
- Split-bailout: not expected (<1500).

**P5-2 — Dark-mode contrast fix.** ✅ **DONE** (`feat/parity-card-pdp-polish`). Closed **P-020** — `primaryDark` → `#E97230`, 4.66:1 on `surfaceDark`, backlog cleared.
- Size: ~30 LOC (token nudge in `tokens.dart` or large-text-only usage) + flip the `contrast_test.dart` row to Pass.
- Risk: **LOW**. Prereqs: none. Goldens: any dark-mode golden touching `primaryDark`.

### SOON (CONFIRMED but backend-data-gated, or PROBABLE pending confirmation)

**P5-3 — PDP delivery-estimate + card/PDP discount data.** Closes **P-007** (delivery ETA row) and lights up the dark **P-008b** UI (original price, lowest-30d).
- Risk: **MED** (touches PDP layout). **Backend dependency:** needs catalog/shipping API fields (delivery ETA, original price, lowest-30d) — UI slot can land NOW with a placeholder, data SOON. Coordinate with a catalog-API follow-up (out of Step-5 UI scope).
- Goldens: PDP buy-box + card.

**P5-4 — Search/category card badges + filter-dimension parity.** Closes **P-009** (Kargo Bedava / campaign / bestseller badges) + confirms **P-010**.
- Risk: **MED**. **Discovery-first (mandatory):** Trendyol `/sr` is 403 — re-confirm with screenshots or an alternate fetch before building (the #59→#60 hypothesis pattern). Backend dependency for free-shipping/campaign flags.

### LATER / PARK

- **P5-5 — Cart suggestions + saved-for-later** (P-011, LOW, PROBABLE) — reuse `ProductListRail`; confirm Trendyol side.
- **P5-6 — Favorite collections** (P-013, LOW, **PARK**) — confirm product intent first (may be an intentional niche-scope omission).
- **P5-7 — Checkout flow-shape review** (P-012, LOW, **PARK**) — only if discovery shows real friction; don't restructure a working 3-DS stepper on taste.
- **Drive-by (Step-1 family, not parity):** remove the empty `mobile/lib/features/orders/` directory (P-019 note).

**Dependencies graph:** P5-1, P5-2 independent (ship in any order). P5-3/P5-4 depend on catalog-API fields (backend, separate track). P5-5/P5-6/P5-7 depend on a Trendyol-side discovery/confirmation pass. **No PR depends on a design-token PR** (tokens are done).

---

## Intentional divergences (documented, NOT filed as gaps — prompt §1.3/§10)

- **D-001 — Cashback chip / Mopro Coin everywhere Trendyol shows discount.** `CashbackChip` on every product card (`product_card.dart:178`), PDP, cart, checkout. Core model (CLAUDE.md §1). Keep.
- **D-002 — No discount-tier nav (5/10/30/50%) on home.** Trendyol's discount-tier strip has no Mopro analog by design (cashback, not discounts). Replaced by mood-stories / editors'-picks / personalized recs.
- **D-003 — Wallet / Cashback-timeline surfaces** (`features/wallet/`, 1550 LOC) — Mopro-only; no Trendyol equivalent. Not a parity surface.
- **D-004 — Seller transparency panel** (`features/seller/`) — Mopro's commission/KDV/net breakdown (CLAUDE.md §4.8) is a Mopro-specific transparency feature.

---

## Honesty note on the audit's limits (prompt §14)

- **Trendyol-side coverage is thin by force, not by laziness.** Only the homepage fetched cleanly (2026-06-03); `/sr`, `/cok-satanlar`, and PDP/category/login-gated pages returned 403 or meta-only. So ~19 of 20 surfaces have **PROBABLE** Trendyol comparisons even though the **Mopro side is CONFIRMED** by code+goldens. The coverage matrix (§2.3) makes this visible. This is exactly the §12 "coverage-constrained" outcome — it is honest, not padded.
- **This audit corrected its own and the prompt's recall errors** (§2.5): the prompt's illustrative "buy box lacks sticky positioning" is false on this branch (P-027); the early project memory's thin-UI assumption was wrong (149 goldens, full design system).
- **Build-PR discovery is the second verification gate.** Every PROBABLE finding (P-009/P-011/P-012/P-013/P-015) must be re-confirmed (screenshots or re-fetch) in its build PR's discovery phase before any code changes — the pattern that caught real misreads across the prior 22 PRs.
- **VERIFIED-COMPLETE is the dominant verdict here, and that is the truthful result.** Mopro is not a Trendyol skeleton awaiting a re-skin; it is a mature, design-systematized, golden-covered, guest-aware app whose remaining parity work is polish and backend-data wiring.

---

*End of Trendyol Parity Audit. No UI changed in this PR (prompt §0/§10). Follow-up parity PRs reference the `P-ID` above; see CONTRIBUTING "Parity audit cadence" and ROADMAP Step 5.*

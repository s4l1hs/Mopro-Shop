# Trendyol Home Parity Audit (post-IA-01) — TRENDYOL_PARITY_HOME

> **Audit-only — NO UI changed in this PR** (audit-then-fix separation). Fixes land as
> separate per-finding prompts scoped from §5, referencing the `HP-ID`.
> Scope: the **restructured Home** after IA-01 (category section → `HomeCategoryRail`;
> Categories bottom-nav tab → **Coin**).
>
> **Status vocabulary** (per prompt §1.3):
> - **CONFIRMED** — real gap; Salih's walk against live Trendyol agrees (severity assigned).
> - **PROBABLE** — the §2 baseline suggests it + the Mopro side is read from source, but the
>   *Trendyol* side is unconfirmed (my Trendyol knowledge is ~May 2025 and Trendyol moves).
>   No severity until walked.
> - **NOT-ACTIONABLE** — intentional Mopro divergence, or already-correct.
>
> **The §2 baseline is PROVISIONAL** — a starting checklist, not ground truth. Salih's walk
> confirms/corrects **every** line. Don't force a "gap" the walk doesn't confirm (§7-4).

---

## TL;DR

- **UPDATE (`feat/home-probable-resolution`) — all 6 PROBABLE rows resolved source-side, no manual walk.** See `docs/internal/home-probable-resolution.md` + §7.
  - **HP-01/02/03 → RESOLVED (audit stale):** the "Sepette %X" pill, the "Çok Satan"
    badge, and the circular pucks were **already implemented** by the post-audit
    catalog vertical (G-3/G-4) — confirmed in `product_card.dart` / `home_category_rail.dart`,
    wired from `ProductSummary`, i18n + tests present. This table was seeded before that landed.
  - **HP-04/05 → NEEDS-DECISION (Salih):** camera/visual-search icon + location
    selector are source-confirmed absent, but resolving them = a **feature** (and for
    HP-05, possibly an **intentional mobile-first IA** omission) — product/IA calls,
    **not** pixel questions, and not fakeable. Handed to Salih.
  - **NEEDS-VISUAL (pixel) residue: 0.** Every PROBABLE row was presence/shape, which
    source + convention settled. **Zero code fixes** this pass.
- ~~**PROBABLE: 6**~~ (original seeding) — HP-01 (no "Sepette %X" basket-discount pill), HP-02 (no per-card
  "Çok Satan" bestseller badge), HP-03 (category pucks are rounded-squares, not circular),
  HP-04 (search bar has no camera/visual-search icon), HP-05 (no location/address selector in
  header), HP-06 (no notification bell in header). All read on the Mopro side from source; the
  Trendyol side is general-knowledge → PROBABLE. *(Resolved per the UPDATE above.)*
- **NOT-ACTIONABLE: 5** — the intentional IA / brand divergences (Coin tab, categories-as-rail,
  cashback chip, coin-balance pill, Mopro brand-orange token). Pre-listed in §4, **not gaps**.
- **Already-matched (VERIFIED, Mopro side): 9** — banner carousel + page indicators, flash-deals
  rail + countdown, for-you/bestseller/recommendation rails + see-all, product-card anatomy
  (1:1 image, discount-% pill, strikethrough original, brand-bold + truncated title, favorite
  heart, rating stars + count, free-shipping badge), mood-stories strip, trust bar, TR-primary
  microcopy, responsive composition. See §3.

**Honest headline:** the restructured Home is already Trendyol-shaped — the open deltas are
**card-merchandising pills + header chrome**, not structural. The two with the most product
value if the walk confirms them are **HP-01** (basket-discount pill) and **HP-02** (bestseller
card badge). Everything else is small styling/affordance polish.

---

## Methodology

Evidence types, descending fidelity (same scheme as `TRENDYOL_PARITY_AUDIT.md`):

1. **Widget-code evidence** — the Flutter widget, cited `file:line`. Highest-fidelity answer to
   "what does Mopro render *today*?" All Mopro-side reads below are on branch
   `docs/trendyol-parity-home-audit`, off `origin/main`.
2. **Golden-test evidence** — the IA-01 Linux-rebaselined goldens
   (`home_{mobile_375,tablet_768,desktop_1440}.png`, `bottom_nav_{light,dark}.png`).
3. **Trendyol evidence** — **none captured in this seeding pass.** The §2 baseline is
   general-knowledge (~May 2025). **This is why every gap is PROBABLE, not CONFIRMED.**
4. **Salih's walk** — the missing high-fidelity Trendyol-side evidence. The §6 slots capture it.

**CONFIRMED requires Trendyol-side evidence (type 3 or 4) on the delta.** Until the walk lands,
the ceiling for any gap here is PROBABLE — even where the Mopro side is certain.

---

## §3 — Self-audit table (Mopro-current vs provisional baseline)

Mopro Home composition, top→bottom (`mobile/lib/features/catalog/screens/home_screen.dart`):
top bar (search pill + coin pill) → mood-stories strip → banner carousel → flash-deals rail →
**category rail** (IA-01) → trust bar → server rails → recommendations → recently-viewed
(→ desktop: editor's picks + footer).

| # | §2 baseline item | Mopro-current (source) | Delta | Status |
|---|---|---|---|---|
| B1 | Brand orange accent; price/discount distinct; white surface | `MoproTokens.primaryLight #CA4E00` / `primaryDark #E97230`; price uses `cs.primary`; discount via shared `DiscountPill`; white `surfaceLight` | Mopro uses its **own** burnt-orange, not Trendyol's `#F27A1A` | **NOT-ACTIONABLE** (D5 — Mopro brand token) |
| B2 | Header: logo + full-width rounded search (placeholder + camera/scan); location selector; cart/fav/notif icons | `_HomeTopBar`: full-width rounded **animated** search pill (rotating hints, search + **mic** icon) + coin pill. No logo, no location selector, no camera icon, no notif bell. Cart/fav live in **bottom nav** | search pill ✅; **no camera icon** → HP-04; **no location selector** → HP-05; **no notif bell** → HP-06; cart/fav-in-bottom-nav is a mobile-IA choice (not a gap) | **PROBABLE** (HP-04/05/06) |
| B3 | Category pucks: horizontal rail of **circular** shortcuts | `HomeCategoryRail` (IA-01): horizontal rail, pucks are **52×52 rounded-square, `BorderRadius 14`**, icon/`iconUrl`, + trailing "Tüm Kategoriler" | Rail **present** (IA-01) ✅; pucks are rounded-square not **circular** | **PROBABLE** (HP-03 — styling parity, not presence) |
| B4 | Auto-advancing hero banners, page indicators, rounded, edge-padded | `_BannerCarousel`: server-driven, 5s autoplay, **`ExpandingDotsEffect` pill dots** (HP-08; was worm), 16:9 mobile / 16:5 desktop, deep-links, desktop hover-pause + chevrons | Matches (indicator → pill dots via HP-08; rounded-corner clip still a nit) | **NOT-ACTIONABLE** (already-correct; indicator closed via HP-08) |
| B5 | Flash-deals rail, often with countdown | `FlashDealsRail`: server-driven, **countdown header** (HH:MM:SS), brand-orange header, `priceOverride` flash price + strikethrough, ended-state collapse | Matches | **NOT-ACTIONABLE** (already-correct) |
| B6 | "Sana Özel" / "Çok Satanlar" / recommendation rails + see-all | Server rails (`homeRailsProvider`) + `_RecommendationsSliver` (personalized/popular title switch) + recently-viewed; each `ProductRail` has `seeAllRoute` | Matches (titles TR-primary; see-all present) | **NOT-ACTIONABLE** (already-correct) |
| B7 | Card: image (aspect); discount-% badge; bestseller + free-cargo badges; rating stars + count; brand-bold + truncated title; original-strikethrough + discounted accent + **"Sepette %X"** pill; favorite heart | `ProductCard`: 1:1 image ✅; `DiscountPill` ✅; **free-shipping** badge ✅; favorites-count badge ✅; `_RatingChip` stars+count ✅; brand `.toUpperCase()` bold ✅; title 2-line ellipsis ✅; strikethrough original ✅; price `cs.primary` ✅; heart top-right ✅; cashback chip (Mopro). **No "Çok Satan" badge; no "Sepette %X" pill** | card anatomy ~95% there; **missing basket-discount pill** → HP-01; **missing bestseller badge** → HP-02 | **PROBABLE** (HP-01/02) |
| B8 | Tight card gutters, consistent rail item width, section rhythm | Mobile rails: 150px card width, 8–12px gutters; section `SizedBox` spacers | Matches (subjective; defer to walk) | **NOT-ACTIONABLE** (already-correct; re-open only if walked) |
| B9 | Bottom nav: Home / [Coin] / Cart / Favorites / Account; active styling | `_MobileShell`: Home / **Coin** / Favorites / Cart / Account; outlined→filled active icons + `nav.*` labels | Coin replaces Categories (intentional); Mopro orders **Favorites before Cart** (vs baseline Cart-then-Fav) — trivial | **NOT-ACTIONABLE** (D1 Coin tab; order nit — note only) |
| B10 | TR-primary section titles + CTAs | `tr-TR.json`: "Senin için seçtiklerimiz", "Kategoriler", "Tüm Kategoriler", "Editörün Seçimleri", "Popüler ürünler", "Son baktıkların", flash-deals | Matches | **NOT-ACTIONABLE** (already-correct) |

---

## §4 — Intentional divergences (NOT-ACTIONABLE by design — NOT gaps)

Pre-listed per prompt §3.3 / §7-3. Do **not** file these as parity gaps; the walk may add more.

- **D1 — Coin bottom-nav tab** replaces Trendyol's Categories tab (IA-01). Categories reachable
  from the Home rail instead. `lib/shell/app_shell.dart:98`.
- **D2 — Categories-as-Home-rail + "Tüm Kategoriler" entry** (IA-01) replaces a dedicated
  Categories tab/grid. `home_category_rail.dart`.
- **D3 — Cashback chip on every product card** (`CashbackChip`, `monthly_coin_minor`) — the
  Mopro perpetual-cashback business model; Trendyol has no equivalent. `product_card.dart:206`.
- **D4 — Coin-balance pill in the Home top bar** (`_CoinBalanceAction` → `/wallet`, authed only)
  — Mopro-specific. `home_screen.dart:334`.
- **D5 — Mopro brand-orange token** (`#CA4E00` / `#E97230`), deliberately *not* Trendyol's
  `#F27A1A`. Accent-hue difference is brand identity, not a parity defect. `design/tokens.dart:10`.

---

## §5 — PROBABLE findings (seeded; await walk to CONFIRM + assign severity)

Each is read on the Mopro side from source; the **Trendyol side is general-knowledge** → PROBABLE.
Suggested severity is a *hint for the walk*, not a commitment.

| HP-ID | Finding (Mopro side, confirmed from source) | Trendyol baseline (PROBABLE) | Suggested sev | Fix surface |
|---|---|---|---|---|
| **HP-01** | ~~Product card has **no "Sepette %X" basket-discount pill**~~ → **RESOLVED / NOT-ACTIONABLE** (source-side pass, `feat/home-probable-resolution`). Audit row **stale**: `product_card.dart` renders `_BasketDiscountPill` ("Sepette %X İndirim", `:229-232/:399-429`) when `basketDiscountPct != null`; `ProductSummary.basketDiscountPct` exists + **all** card call sites wire it (`product_rail`/`product_list_rail`/`product_grid`); i18n `product.basket_discount`; tested in `product_card_test.dart`. Landed by the G-3/CT-09 catalog vertical **after** this audit was seeded. | Trendyol shows a "Sepette %X" basket-price pill on many cards *(convention, ~May 2025 — not visually verified)* | — | **DONE** (audit stale) |
| **HP-02** | ~~Product card has **no per-card "Çok Satan"/bestseller badge**~~ → **RESOLVED / NOT-ACTIONABLE** (source-side). Stale: `product_card.dart:153/:329-362` stamps `_BestsellerBadge` ("Çok Satan") when `isBestseller==true`; `ProductSummary.isBestseller` wired at all call sites; i18n `product.bestseller`; signal flows P-029/P-031. Landed (G-3) post-audit. | Trendyol stamps a "Çok satan" ribbon on bestselling cards *(convention, ~May 2025 — not visually verified)* | — | **DONE** (audit stale) |
| **HP-03** | ~~Category pucks are **rounded-square 52×52 (radius 14)**~~ → **RESOLVED / NOT-ACTIONABLE** (source-side). Stale: `home_category_rail.dart:133` is now `shape: BoxShape.circle` ("Trendyol-style circular category puck (G-4)"). | Trendyol category pucks are **circular** *(long-standing convention, ~May 2025 — not visually verified)* | — | **DONE** (audit stale) |
| **HP-04** | Search pill has search + **mic** icon, **no camera/visual-search icon** (`home_screen.dart:297/:328`) — source-confirmed absent | Trendyol search bar has a **camera** (visual search) icon *(convention, ~May 2025 — not visually verified)* | LOW | **NEEDS-DECISION (Salih)** — visual-search **feature** (route + image pipeline) vs. omit; a camera icon wired to nothing is a fake affordance → not fixed on a guess |
| **HP-05** | **No location/address selector** in the Home header (`_HomeTopBar` = search + `NotificationBell` + coin) — source-confirmed absent | Trendyol header has a location/address selector *(convention, ~May 2025 — not visually verified)* | LOW | **NEEDS-DECISION (Salih)** — address-on-Home **feature** vs. **intentional mobile-first IA** omission (cart/fav already in bottom nav) |
| **HP-06** | ~~**No notification bell** in the Home header~~ → **RESOLVED** (Sprint A): `NotificationBell` mounted in `_HomeTopBar` (mobile) + `WebHeader` (desktop), reusing the Tranche-2a `unreadNotificationCountProvider` + `NotificationBadge`; taps to `/account/notifications`. Always-visible, badge auto-hidden for guests. See `docs/internal/hp06-notification-bell.md`. | Trendyol header has a notifications bell | LOW | **DONE** — header chrome (reused the shipped inbox stack) |
| **HP-07** | ~~Desktop/tablet product rails were a **static fixed-column grid** (`RailLayout.grid` — 5-col/`maxItems:10` desktop, 3-col/6 tablet), clipping the set with no horizontal scroll~~ → **RESOLVED** (Sprint B): `RailLayout.carousel` — lazy horizontal `ListView.builder` (full set up to `maxItems`) + desktop **hover chevrons** (white circular floating cards, `HoverRegion` fade, slide one viewport, gated at extents). Tablet = scroller without chevrons; mobile scroller untouched. See `docs/internal/sprint-b-rail-carousel.md`. | Trendyol web rails scroll horizontally with left/right hover chevrons | **HIGH** (interaction parity) | **DONE** — `ProductRail` (`product_rail.dart`) |
| **HP-08** | ~~Banner carousel indicator used the **`WormEffect`** sliding dot (`home_screen.dart`)~~ → **RESOLVED** (Closeout): `ExpandingDotsEffect` — Trendyol-style **pill dots** (inactive dots, active expands to a brand-`colorScheme.primary` pill). Carousel logic/aspect untouched. See `docs/internal/home-closeout.md`. | Trendyol banner uses thin-line / pill page dots | **MED** | **DONE** — `_BannerCarousel` indicator |
| **HP-09** | ~~Desktop footer info links were **dead stubs** (`home_footer.dart` `onPressed: () {}`)~~ → **RESOLVED** (Closeout): `help` → `/help`, `privacy` → `/help/article/privacy-and-tracking` (canonical, shared w/ consent + privacy settings); `about` + `terms` **DEFER** to `/help` (no dedicated page — nearest public hub; not built for a LOW item). No dead `onPressed`. See `docs/internal/home-closeout.md`. | Trendyol footer links reach real destinations | **LOW** | **DONE** (about/terms DEFER) — `home_footer.dart` |

> **Walk note:** HP-04/05/06 may be **NOT-ACTIONABLE** if Salih decides Mopro's mobile-first
> bottom-nav IA deliberately omits header chrome — record that call in §6 and reclassify.

---

## §6 — Walk-findings slots (Salih — paste live-Trendyol observations here)

> Format mirrors `TRENDYOL_PARITY_AUDIT.md` findings. One block per observation. On confirming
> a §5 item, change its **Status** to CONFIRMED and set **Severity**; add **new** items as
> HP-07, HP-08, … For an item the walk decides is intentional, set **NOT-ACTIONABLE** + why.

```
### HP-NN — <one-line title>
- **Surface/region:** Home › <header | category rail | banner | flash deals | rail | card | bottom nav>
- **Trendyol (live):** <what Trendyol does — screenshot ref / observation>  [walk date: ____]
- **Mopro (current):** <what Mopro does — file:line if known>
- **Delta:** <the difference>
- **Status:** CONFIRMED | PROBABLE | NOT-ACTIONABLE
- **Severity:** HIGH | MED | LOW   (only if CONFIRMED)
- **Notes:** <intentional? backend-gated? golden-flip? depends-on?>
```

<!-- ── Salih's confirmations of the §5 seed ──────────────────────────────── -->
<!-- HP-01 … paste here -->
<!-- HP-02 … paste here -->
<!-- HP-03 … paste here -->
<!-- HP-04 … paste here -->
<!-- HP-05 … paste here -->
<!-- HP-06 — RESOLVED in Sprint A (feat/notification-bell-hp06). NotificationBell
     in both headers, wired to unreadNotificationCountProvider, routing to
     /account/notifications; gated like cart/favorites (always-visible, badge
     hidden at count 0). Discovery: docs/internal/hp06-notification-bell.md -->

<!-- ── New findings from the walk (HP-07+) ───────────────────────────────── -->
<!-- HP-07 — RESOLVED in Sprint B (feat/desktop-rail-carousel). Desktop/tablet
     rails: static grid → horizontal carousel (RailLayout.carousel) with desktop
     hover chevrons + extent gating; mobile scroller untouched. Discovery:
     docs/internal/sprint-b-rail-carousel.md -->
<!-- HP-08 — RESOLVED in Closeout (feat/home-walk-closeout). Banner indicator
     WormEffect → ExpandingDotsEffect (pill dots, brand-primary active). -->
<!-- HP-09 — RESOLVED in Closeout (feat/home-walk-closeout). Footer dead-stub
     links routed: help → /help, privacy → /help/article/privacy-and-tracking;
     about + terms DEFER to /help (no dedicated page). Discovery:
     docs/internal/home-closeout.md -->
<!-- HP-08 … -->

---

## §7 — Summary (status counts) + fix-prompt readiness

**Counts (after the source-side resolution pass, `feat/home-probable-resolution`):**

| Status | Count | IDs |
|---|---|---|
| CONFIRMED (open) | 0 | — |
| PROBABLE (open) | 0 | — (all 6 resolved source-side) |
| RESOLVED / already-implemented (audit stale) | 6 | HP-01, HP-02, HP-03 (card pill / bestseller badge / circular pucks — G-3/G-4); HP-06/07/08/09 (Sprint A/B/Closeout) |
| NEEDS-DECISION (Salih — feature/IA, not pixel) | 2 | HP-04 (visual-search camera), HP-05 (location selector) |
| NEEDS-VISUAL (pixel — your eyes) | 0 | — every PROBABLE row was presence/shape, source-settled |
| NOT-ACTIONABLE (divergence) | 5 | D1 … D5 |
| Already-matched (Mopro VERIFIED) | 9 | B4, B5, B6, B8, B10 + card-anatomy/carousel/rails/stories in B7/B3 |

**Source-side resolution (no manual walk needed for these):** see
`docs/internal/home-probable-resolution.md`. HP-01/02/03 were closed by the
post-audit catalog vertical (the audit table was stale); HP-04/05 are product/IA
decisions (build a feature vs. intentional mobile-first omission), **not** pixel
questions — handed to Salih. **Zero code fixes; zero NEEDS-VISUAL residue for Home.**

**Salih's decisions (not pixel-peeping):**
1. **HP-04** — build visual-search (camera), or confirm intentional omission?
2. **HP-05** — add an address/location selector to Home, or confirm the mobile-first bottom-nav IA deliberately omits header chrome?

---

## §8 — Where this fits

Parity track, restructured Home. Next: **Salih walks Home against live Trendyol** (emulator +
phone), confirms/corrects §5, fills §6, assigns severities → I turn the CONFIRMED-HIGH/MED set
into per-finding fix prompts (same audit-then-fix loop as the deploy arc and the original
`TRENDYOL_PARITY_AUDIT.md`).

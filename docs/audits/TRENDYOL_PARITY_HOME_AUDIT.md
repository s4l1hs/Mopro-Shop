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

- **CONFIRMED: 0** — nothing yet; this doc is **seeded, awaiting Salih's walk**. Every gap
  below is **PROBABLE** until the walk confirms it and assigns a severity.
- **PROBABLE: 6** — HP-01 (no "Sepette %X" basket-discount pill), HP-02 (no per-card
  "Çok Satan" bestseller badge), HP-03 (category pucks are rounded-squares, not circular),
  HP-04 (search bar has no camera/visual-search icon), HP-05 (no location/address selector in
  header), HP-06 (no notification bell in header). All read on the Mopro side from source; the
  Trendyol side is general-knowledge → PROBABLE.
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
| B4 | Auto-advancing hero banners, page indicators, rounded, edge-padded | `_BannerCarousel`: server-driven, 5s autoplay, `AnimatedSmoothIndicator` worm dots, 16:9 mobile / 16:5 desktop, deep-links, desktop hover-pause + chevrons | Matches (no rounded-corner clip / edge inset on mobile — minor) | **NOT-ACTIONABLE** (already-correct; rounding is a nit, fold into HP-03 if walked) |
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
| **HP-01** | Product card has **no "Sepette %X" basket-discount pill** (`product_card.dart` price block ends at strikethrough + `DiscountPill` + cashback) | Trendyol shows a "Sepette %X" basket-price pill on many cards | MED | card widget + backend basket-discount field |
| **HP-02** | Product card has **no per-card "Çok Satan"/bestseller badge** (bestseller *rail/sort* exists — P-029/P-031 — but no card-level badge) | Trendyol stamps a "Çok satan" ribbon on bestselling cards | LOW–MED | card overlay + `is_bestseller` signal |
| **HP-03** | Category pucks are **rounded-square 52×52 (radius 14)**, not circular (`home_category_rail.dart:125`) | Trendyol category pucks are **circular** | LOW | `_CategoryPuck` shape only (golden-flip) |
| **HP-04** | Search pill has search + **mic** icon, **no camera/visual-search icon** (`home_screen.dart:322`) | Trendyol search bar has a **camera** (visual search) icon | LOW | top-bar icon (+ visual-search route, likely DEFER) |
| **HP-05** | **No location/address selector** in the Home header (`_HomeTopBar` = search + coin only) | Trendyol header has a location/address selector | LOW | header chrome (needs address model — likely DEFER) |
| **HP-06** | ~~**No notification bell** in the Home header~~ → **RESOLVED** (Sprint A): `NotificationBell` mounted in `_HomeTopBar` (mobile) + `WebHeader` (desktop), reusing the Tranche-2a `unreadNotificationCountProvider` + `NotificationBadge`; taps to `/account/notifications`. Always-visible, badge auto-hidden for guests. See `docs/internal/hp06-notification-bell.md`. | Trendyol header has a notifications bell | LOW | **DONE** — header chrome (reused the shipped inbox stack) |

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
<!-- HP-07 … -->
<!-- HP-08 … -->

---

## §7 — Summary (status counts) + fix-prompt readiness

**Counts (seeded, pre-walk):**

| Status | Count | IDs |
|---|---|---|
| CONFIRMED | 0 | — (await walk) |
| PROBABLE | 6 | HP-01 … HP-06 |
| NOT-ACTIONABLE (divergence) | 5 | D1 … D5 |
| Already-matched (Mopro VERIFIED) | 9 | B4, B5, B6, B8, B10 + card-anatomy/carousel/rails/stories in B7/B3 |

**"Ready for fix prompts" — populated after the walk** (CONFIRMED-HIGH/MED first):

1. _(await walk)_ — likely **HP-01** (basket-discount pill) if CONFIRMED MED — highest product value.
2. _(await walk)_ — likely **HP-02** (bestseller card badge) if CONFIRMED.
3. _(await walk)_ — **HP-03** (circular pucks) — pure UI, golden-flip, no backend.

Until the walk lands, **no fix prompts are scoped** (§7-4: don't invent severities for
unconfirmed items). HP-03 is the only zero-dependency pure-UI candidate; HP-01/HP-02 likely
need a backend signal (basket-discount field / `is_bestseller`).

---

## §8 — Where this fits

Parity track, restructured Home. Next: **Salih walks Home against live Trendyol** (emulator +
phone), confirms/corrects §5, fills §6, assigns severities → I turn the CONFIRMED-HIGH/MED set
into per-finding fix prompts (same audit-then-fix loop as the deploy arc and the original
`TRENDYOL_PARITY_AUDIT.md`).

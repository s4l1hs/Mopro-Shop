# Home Walk Closeout — Banner Indicators (MED) + Footer Links (LOW) — discovery

> Final two Home-walk gaps: swap the banner "worm" indicator for Trendyol-style
> pill dots; route the footer's dead-stub links. Verified on
> `feat/home-walk-closeout`.

## Banner indicator (MED)

- **Widget:** `_BannerCarousel` (`home_screen.dart:358`). A `PageView.builder`
  inside an `AspectRatio` (16:9 mobile / 16:5 desktop) + a `Stack`; desktop adds
  hover-pause + prev/next chevrons. **Carousel logic/aspect stays untouched.**
- **Indicator today** (`home_screen.dart:443`): `AnimatedSmoothIndicator` with
  **`WormEffect`** (7×7 dots, white active / white-α128 inactive), `Positioned`
  bottom-center.
- **Target:** `ExpandingDotsEffect` (`smooth_page_indicator` 1.2.1, already
  imported) — inactive small dots, **active expands to a pill** = the Trendyol
  "pill dots" look. Active dot uses the **brand token** (`colorScheme.primary`);
  inactive stay translucent white for contrast over photos. Position / count /
  `activeIndex` tracking unchanged.

## Footer links (LOW)

- **Widget:** `home_footer.dart` — `_FooterLink` (`:50`) has `onPressed: () {}`
  (dead stub) for 4 links: `footer.about`, `footer.help`, `footer.privacy`,
  `footer.terms`. Desktop-only footer.
- **Existing routes (router scan):**
  - `/help` → `HelpIndexScreen` (public, not hard-gated). ✅
  - `/help/article/:slug` → `HelpArticleScreen`. The **canonical privacy
    article** slug is `privacy-and-tracking` (used by `consent_banner.dart:71`
    and `privacy_settings_screen.dart:124`). ✅
  - No `/about`, no `/terms`, no public privacy-policy page exist.
- **Wiring decision:**
  - `footer.help` → `context.go('/help')` — **WIRED** (real public hub).
  - `footer.privacy` → `/help/article/privacy-and-tracking` — **WIRED**
    (canonical privacy content, reused from consent/settings).
  - `footer.about`, `footer.terms` → **DEFER** to `/help` (nearest existing
    public info hub). No dedicated About/Terms page exists; building them is out
    of scope for a LOW item (§3.2 / anti-goal #2). No dead `onPressed` remains.
- i18n: labels already exist (`footer.about/help/privacy/terms`); no new keys.

## Affected goldens (predict)

- **`home_mobile_375` + `home_tablet_768` + `home_desktop_1440`** — all render
  the banner (the golden test seeds 2 banners), so the indicator region flips
  (worm → pill dots). FLIP ×3.
- **Footer change is routing-only → no visual diff → no golden impact** (the
  desktop footer in `home_desktop_1440` flips only from the banner indicator).
- No dedicated banner golden; `seller_storefront`/`consent` goldens use their own
  banners (the home `_BannerCarousel` is private) → **no flip**.
- **Merge note:** these 3 home goldens also move in the open Sprint B PR (#136,
  rails). Whichever merges second needs a golden re-baseline — expected, not a
  correctness issue here (each PR is correct vs `main`).

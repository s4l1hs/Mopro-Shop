# PDP UX — PD-09 sticky buy-box · PD-10 recently-viewed rail · PD-06 mobile thumbnails (discovery)

> Lane A1 (`feat/pdp-ux`). Three PDP UX adds on existing data — no codegen, no
> shared-widget internals (`ProductCard`/`FilterPanel` untouched; rails mount
> `ProductCard` read-only via the existing `ProductListRail`).

## 1. The PDP today

`product_detail_screen.dart` (one file, mobile + wide):

- **Mobile** (`_buildMobile`): `NestedScrollView` — pinned `SliverAppBar` whose
  flexible space is **`PdpImageGallery`** (PageView + worm dots + tap-fullscreen +
  Hero; **no thumbnail strip** → PD-06), `_BuyBox` sliver, pinned tab bar, 4 tabs.
  `bottomNavigationBar: PdpStickyCta` — **mobile already pins price + add-to-cart**;
  PD-09's mobile half is pre-satisfied.
- **Wide** (`_buildWide`): `SingleChildScrollView` (`_wideScroll`) → two-column row:
  gallery (`PdpImagePager` — already has a thumbnail strip + arrows + hover-zoom)
  and a 480dp buy-box column measured via `_buyBoxKey`. The **gallery
  sticky-translates** within the taller column (`top = _scrollOffset.clamp(0,
  contentH − galleryH)`) — locked by `pdp_screen_sticky_gallery_test.dart`
  (pins → releases → re-pins) and the audit calls replacing it a UX redesign.
  Once you scroll past the row (tabs/reviews/similar), **no buy affordance remains
  on screen** → that's the PD-09 desktop gap.

## 2. PD-09 — sticky buy-box (desktop)

**Decision-consistent approach:** keep the sticky-gallery mechanics untouched and
add a **condensed sticky buy-bar** (new widget `PdpStickyBuyBar`) that slides in at
the viewport top on the wide layout once the buy-box has scrolled out of view —
thumbnail + title + price + add-to-cart. This is what Trendyol desktop does
functionally (the buy affordance follows the scroll), without re-architecting the
two-column Stack. Signals already exist: `_scrollOffset` (state, updated by the
`_wideScroll` listener) and `_buyBoxHeight` (post-frame measure). Visibility rule:
`_scrollOffset > buyBoxBottom` (≈ row top + measured buy-box height).

Guards: `pdp_screen_composition_test.dart` asserts desktop has **no `PdpStickyCta`**
— the new bar is a distinct widget, so that assertion stays true. PDP goldens
(`pdp_two_col_*`) capture scroll=0 where the bar is hidden → no flips.

## 3. PD-10 — recently-viewed rail

Data exists end-to-end (Tranche 4c): `recentlyViewedProvider`
(`features/home/recently_viewed_provider.dart`) fetches `/me/recently-viewed`
(limit 20), already gated on flag+auth+consent and **error→empty** (rail hides;
never an error state). Home renders it via `ProductListRail` (read-only
`ProductCard` mount) with the existing i18n key
`home.rails.recently_viewed.title`.

PDP mount: a `_RecentlyViewedRail(excludeProductId)` consumer —
- wide: below `_SimilarProductsRail`;
- mobile: in the description tab below the related rail (where rails live on mobile).

Filter the **current product** out (you just viewed it — echoing it back is noise;
the similar rail applies the same `p.id != productId` filter). Zero-space when
empty/unauthed/no-consent. No new endpoint, no codegen, no provider changes.

## 4. PD-06 — mobile gallery thumbnail strip

`PdpImageGallery` (mobile-only usage) already owns a `PageController`. Add a
bottom-overlaid thumbnail strip (56dp, horizontal, tap → `animateToPage`, active
border highlight synced via a page listener), shown only when `imageUrls.length >
1`, replacing the worm dots in that case (dots remain for the 1-image no-op case —
they already render only when >1, so effectively: strip supersedes dots). Desktop
(`PdpImagePager`) already has thumbnails — untouched.

Goldens: no golden covers the mobile gallery (PDP goldens are desktop two-col;
`recs_pdp_*` goldens render `ProductListRail` standalone) → expected zero flips.

## 5. Coordination (lane contract)

- OWNS: `product_detail_screen.dart`, `pdp_image_gallery.dart`, new
  `pdp_sticky_buy_bar.dart`, a PDP-local recently-viewed mount.
- NOT TOUCHED: `ProductCard`, `FilterPanel`, `ProductListRail` internals, PLP/
  search, favorites, `.github`, `api/openapi.yaml` (no codegen).

## 6. Plan (one commit per concern)

1. This discovery doc.
2. **PD-09** — `PdpStickyBuyBar` + wide-layout wiring + widget/behavior test.
3. **PD-10** — `_RecentlyViewedRail` mounts (wide + mobile description tab) + test.
4. **PD-06** — thumbnail strip in `PdpImageGallery` + test.
5. Audit (PD-06/09/10 → resolved) + ledger + gates + PR.

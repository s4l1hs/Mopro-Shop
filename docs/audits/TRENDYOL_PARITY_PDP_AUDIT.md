# Trendyol Parity Audit — PDP (Product Detail)

> **Audit only — no code.** Self-audit of the PDP against a **provisional**
> Trendyol baseline (§2), seeded for Salih's walk. IDs **PD-NN**, #09 walk format.
> Sibling of the PLP/Search audits. `src` = Mopro code fact; `walk` = Salih's
> visual/interaction observation. Markup of `/p-*` may be SSR-readable — flagged
> where it'd help, but the PDP's heavy areas (gallery zoom, variant pickers,
> reviews) are **visual** → walk-gated.
>
> **Surface (source):** `ProductDetailScreen` + `_ProductDetailBody` (mobile
> `NestedScrollView` / desktop two-column sticky-gallery) · `PdpImageGallery`
> (mobile) / `PdpImagePager` (desktop) · `PdpPriceBlock` · `PdpVariantSelector` ·
> `PdpStickyCta` · `PdpDeliveryInfo` · `PdpSellerCard` · `PdpReviewsTab` +
> `RatingDistributionHistogram` · `PdpQaTab` · `_SimilarProductsRail`.

---

## §0 — Legend

- **Source** — `src` (code fact) · `walk` (Salih, visual/interaction).
- **Confidence** — **CONFIRMED** (structural source fact) · **PROBABLE**
  (visual/interaction — awaits the walk) · **MATCHED** (parity, verified in
  source) · **NOT-ACTIONABLE** (intentional divergence).

---

## §1 — Summary

- **The PDP is largely built** — gallery, title/brand/rating→reviews,
  price (strikethrough + lowest-30d), variants, buy box + sticky CTA, delivery-
  ETA, seller, similar rail, **reviews (histogram + sort + helpful)**, **Q&A**.
- **#77–#103 arc confirmed MATCHED (§3):** P-007 delivery-ETA, P-030 lowest-30d,
  P-032 strikethrough.
- **CONFIRMED gaps (src): 1 open** — PD-03 no basket-discount on the PDP price
  block. (**PD-01** specs ✅ resolved for the renk slice; **PD-07** reviewer name +
  photos ✅ resolved — both below.)
- **CONFIRMED-src deltas: 1** — PD-04 seller card: official badge **✅ RESOLVED**
  (`feat/plp-17-official-seller`); **seller rating** still missing (open)
  (ties PLP-17).
- **PROBABLE (await walk): 4** — PD-02 variant pickers (text chips vs swatches),
  PD-05 installments, PD-06 gallery (video / mobile thumbnails), PD-09 desktop
  sticky buy-box.
- **NOT-ACTIONABLE: 3** — coin/cashback card, brand tokens, trust badges vs a
  detailed cargo/return block.
- **✅ SEED WALK-FIXTURE ADDED (§6)** — `chore/pdp-seed` (`pdp-walk-extras.sql`)
  enriches MP-S001: 5 variants (incl. OOS) + 3–6-image galleries + 7 varied
  reviews. **Variant selector + reviews now exercisable** (live-verified).
- **✅ PD-06 RESOLVED (`fix/pdp-readpath-contract`)** — `GET /products/{id}` now
  emits the flat, spec-conformant `Product` with variant **`image_urls`**
  (CDN-mapped from `image_keys`), replacing the legacy `{product, variants,
  translations,…}`/`image_keys` envelope that matched neither the spec nor the
  mobile client. **Gallery (+ the whole PDP parse) now unblocked.** A new
  **live-handler contract test** guards the response shape (the F-021 fixture test
  couldn't). **PD-07** (reviewer name + photos) is the scoped follow-up.

---

## §2 — Self-audit (Mopro current vs baseline)

| ID | Baseline (Trendyol) | Mopro current (`src`) | Delta | Status | Sev |
|---|---|---|---|---|---|
| — | Gallery: carousel + thumbs + zoom + video | mobile `PdpImageGallery` (PageView + dots + tap-fullscreen + Hero); desktop `PdpImagePager` (thumbnail strip + arrows + **hover-zoom 2× lens**) | mobile has **no thumbnail strip**; **no video**; no lightbox beyond fullscreen | **PD-06** | LOW–MED |
| — | Title: brand(linked) + title + rating→reviews + fav + share | brand `InkWell`→brand search, title, rating row→`_scrollToReviews`, favorite, `MoproShareButton` | — | **MATCHED** | — |
| — | Price: strikethrough + discount + "Sepette %X" + cashback + lowest-N | `PdpPriceBlock` (strikethrough **P-032** + discount pill + **lowest-30d P-030**) + `_CashbackCard` | **no basket-discount "Sepette %X"** on the PDP price block (product carries `basketDiscountPct`). NB: as of CT-09 the basket discount is now a **charged** seller-funded discount (applied in cart/checkout/order; migration 0091), so surfacing the pill on the PDP would be honest — remaining work is display-only (this PDP surface), out of CT-09's pricing-path scope. | **PD-03** (display-only) | MED |
| — | Variants: colour swatches + size pickers + OOS | `PdpVariantSelector` — one `FilterChip` per variant ("colour / size" label), OOS struck-through + disabled (**P-015**); only renders when `variants.length > 1` | **text chips, not swatch/size pickers**; flat variant list, not attribute groups (ties **PLP-13**) | **PD-02** | MED |
| — | Buy box: ATC (sticky) + qty + installments | mobile `PdpStickyCta` (bottom bar); desktop ATC + favorite + `_QuantityStepper`; **desktop gallery** sticky-translates | **desktop buy-box itself not pinned**; **no installments** | **PD-09 / PD-05** | MED |
| — | Delivery: ETA + cargo + return | `PdpDeliveryInfo(eta)` (**P-007**) + `_TrustBadges` (secure / return / free-ship) | trust badges, not a **detailed cargo/return policy** block | **NOT-ACTIONABLE** (D3) | — |
| — | Seller: name + rating + official badge | `PdpSellerCard(name, official✓, →storefront)` | official badge **✅ RESOLVED** (`feat/plp-17-official-seller`: `Product.seller_official` → verified check on `PdpSellerCard`, ties **PLP-17**); **seller rating still open** | **PD-04** (partial) | LOW–MED |
| — | Specs: key-spec attribute table | **RESOLVED for the PLP-13 `renk` slice** (`feat/plp-13-pdp-specs`): the specs tab now renders `Product.attributes` (`_SpecsTab` — name/value table + empty-state) on mobile + desktop; `_StubTab` removed. Backed by the normalized attribute model (0089) + the facet read-path. More attribute types arrive with PLP-13 Phase 2. | **PD-01** | **HIGH → resolved (renk)** |
| — | Reviews: breakdown + photos + sort/filter + helpful | `PdpReviewsTab` — `RatingDistributionHistogram` + sort menu + paginated list + **helpful votes** + write-review (window-gated) + **reviewer name + photos (PD-07)** | **PD-07 RESOLVED** (`feat/pd-07-review-metadata`): reviews now return `reviewerName` (masked `identity.Service.GetMe`) + `photoUrls` (`attachments.Service.ListByEntity`, CDN-mapped) — §5-safe in-process calls, **no codegen** (the reviews endpoint is hand-written/not in the spec) — rendered as a name header + photo strip; live-handler contract test guards both. Remaining: rating-filter (sort only) | **PD-07 → resolved** | MED |
| — | Similar / recommended + recently-viewed + Q&A | `_SimilarProductsRail` + mobile related rail (co-view) + **`PdpQaTab`** | **no recently-viewed on PDP** (it's a home rail) | **PD-10** | LOW |

---

## §3 — Already shipped (#77–#103) — MATCHED (verified)

- **P-007 delivery-ETA** — `PdpDeliveryInfo(product.deliveryEta)`, gated on non-null. ✅
- **P-030 lowest-30d** — `PdpPriceBlock.lowestIn30DaysMinor` (per-variant). ✅
- **P-032 strikethrough** — `PdpPriceBlock` original-price strikethrough + discount-% pill. ✅
- **P-015 OOS variants** — struck-through + disabled in `PdpVariantSelector`. ✅
- Also matched: rating→reviews jump, brand→search link, SEO/JSON-LD (`productJsonLd`),
  share, favorite, `_SimilarProductsRail`, Q&A, cashback preview, quantity stepper.

---

## §4 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — Coin/cashback card** (`_CashbackCard`, perpetual-cashback model) in the
  buy box — Mopro's analog to Trendyol's installment messaging.
- **D2 — Brand-orange tokens** on price/links.
- **D3 — Trust badges** (secure payment / easy return / free shipping) in place of
  a verbose cargo/return-policy block.

> *PD-05 (installments) is listed PROBABLE, not NOT-ACTIONABLE: confirm in the
> walk whether the cashback card is considered a sufficient substitute or whether
> an instalment row is still wanted.*

---

## §5 — Already-matched (VERIFIED from source)

Mobile gallery (carousel + dots + tap-fullscreen + Hero) · desktop gallery
(thumbnails + arrows + hover-zoom) · title + linked brand + rating→reviews +
favorite + share · price (P-032 + P-030 + discount pill) · stock pill (in/low/out)
· delivery-ETA (P-007) · cashback preview · variant chips + OOS (P-015) · mobile
sticky CTA · desktop sticky-translate gallery · quantity stepper · seller
storefront link · similar rail + co-view related · reviews (histogram + sort +
helpful + write) · Q&A · trust badges · SEO/JSON-LD/OpenGraph.

---

## §6 — Seed adequacy — ✅ ADDRESSED (`chore/pdp-seed`, `pdp-walk-extras.sql`)

The walk fixture now lives in `scripts/seed/data/pdp-walk-extras.sql` (dev-only,
idempotent; apply after `make seed`). It enriches **MP-S001** (Nike Dri-FIT,
product 15):

| Area | Seeded reality (live-verified via core-svc) | Walk status |
|---|---|---|
| **Gallery** | 5 variants carry **3–6** images each | **exercisable** ✅ — **PD-06 resolved**: the server now emits `Variant.image_urls` (CDN-mapped) ↓ |
| **Variants** | **5** variants (Siyah S/M/L + Beyaz M + Lacivert M) → `PdpVariantSelector` renders; **Siyah/L `stock=0`** = OOS (P-015); Siyah carry a strikethrough (`original_price_minor`) | **exercisable** ✅ |
| **Reviews** | **7** reviews, ratings **5/5/5/4/4/3/2** (histogram `{2:1,3:1,4:2,5:3}`, avg 4.0), varied `helpful_count`; `products.rating_avg/rating_count` matched | **exercisable** ✅ (sort/histogram/helpful) |

> **✅ PD-06 RESOLVED — gallery unblocked (`fix/pdp-readpath-contract`).**
> `GET /products/{id}` was a legacy `{product, variants, translations,…}` envelope
> with variant `image_keys`/`cover_image_url` — matching neither the OpenAPI flat
> `Product` nor the generated mobile client (both flat, `Variant.image_urls`
> required), so the strict parse failed and the PDP never rendered end-to-end. The
> handler now emits the flat spec `Product` with **`image_urls`** (CDN-mapped from
> `image_keys`), title/description locale-resolved. A **live-handler contract test**
> guards it (the fixture-only F-021 test could not). **Review photos (PD-07) are
> still not surfaced** by `ListReviews` →
> not seeded. Both are post-walk read-path fixes. Discovery: `docs/internal/pdp-seed.md`.

---

## §7 — Walk-findings slots (Salih; #09 format)

> After the seed extension, walk the gallery (zoom/fullscreen/thumbnails), variant
> pickers (swatch feel, OOS), the buy box (sticky behaviour, ATC), reviews (photos,
> filter), and confirm PD-02/05/06/09. New items continue at **PD-11+**.

```
### PD-NN — <one-line title>
- **Surface/region:** PDP › <gallery | title | price | variants | buy box | delivery | seller | specs | reviews | qa | similar>
- **Trendyol (live):** <observation>  [walk date: ____]
- **Mopro (current):** <file:line if known>
- **Delta / Status / Severity / Notes>
```

<!-- PD-02 — confirm Trendyol's colour swatches + separate size picker. -->
<!-- PD-05 — installments row vs the cashback card — wanted or not? -->
<!-- PD-06 — gallery video? mobile thumbnail strip? -->
<!-- PD-09 — desktop buy-box sticky on scroll? -->
<!-- PD-11 … -->

---

## §8 — Prioritized fix list (after seed + walk)

1. **Seed extension (prerequisite)** — multi-image + multi-variant + reviews (own task).
2. **PD-01 specs/attributes table** — HIGH; the stub tab. **Ties to PLP-13** — the
   normalized attribute model feeds both the PLP facets *and* this spec table.
3. **PD-07 photo reviews** + rating-filter — backend (review images) + UI.
4. **PD-03 basket-discount** on the PDP price block (data already on the product).
5. **PD-02 variant pickers** (swatch/size) — ties PLP-13; **PD-04 seller
   rating/official** — ties PLP-17 (backend flag).
6. **PD-05 / PD-06 / PD-09** — per the walk (installments, gallery video/thumbs,
   desktop sticky buy-box). LOW–MED.

> **Cross-surface ties:** PD-01/PD-02 ride the **PLP-13 attribute model**;
> PD-04 rides the **PLP-17 official-seller flag**. Building those backends lights
> up the PLP *and* the PDP. No fixes in this PR.

# PDP PROBABLE resolution — source-side pass (not a visual walk)

Applies the Home method (`home-probable-resolution.md`): Mopro side from code (fact)
× Trendyol convention (provisional, ~May 2025, *not visually verified*) → verdict.
No fabricated observations.

## Per-row resolution

### PD-02 — variant pickers: text chips, not colour swatches / size pickers → CONFIRMED, DEFER (needs colour-attribute data; ties PLP-13)
- **Mopro (fact):** `PdpVariantSelector` renders one `FilterChip` per variant (label
  "colour / size"), OOS struck-through + disabled (P-015), only when
  `variants.length > 1`. Flat variant list, **not** attribute-grouped swatches.
- **Trendyol (provisional):** colour swatches + a separate size picker *(convention,
  ~May 2025 — not visually verified)*.
- **Verdict:** a genuine categorical gap (text chips vs swatches), but rendering
  swatches needs a **per-variant colour→swatch signal** (the normalized attribute
  model, PLP-13 Phase 2 — `renk` exists but isn't surfaced per-variant as a colour).
  Not a pure per-surface UI fix → **DEFER to PLP-13 Phase 2**. Flagged, not guessed.

### PD-03 — no "Sepette %X" basket-discount pill on the PDP price block → DEFER (needs spec/codegen + backend) — *audit said "display-only"; that's stale*
- **Mopro (fact):** `pdp_price_block.dart` renders strikethrough + `DiscountPill`
  (P-006) + lowest-30d (P-030); **no basket-discount pill**. **Discovery shift:** the
  PDP's flat `Product` model (`GET /products/{id}`) has **no `basketDiscountPct`
  field** — only the card's `ProductSummary` does. The audit assumed the product
  "carries `basketDiscountPct`" and called PD-03 *display-only*; on the PDP it isn't.
- **Trendyol (provisional):** "Sepette %X" on the PDP price area *(convention)*.
- **Verdict:** surfacing it needs `basket_discount_pct` added to the spec `Product`
  (**codegen**) + the backend handler emitting it → serializes per §3, **not** a
  display-only UI fix. **DEFER** (codegen+backend vertical). Flagged.

### PD-04 — seller rating missing on the seller card → DEFER (needs backend seller-rating signal)
- **Mopro (fact):** `PdpSellerCard(name, official✓ → storefront)`; official badge
  RESOLVED (PLP-17). **No seller rating** rendered.
- **Trendyol (provisional):** seller name + **rating** + official badge *(convention)*.
- **Verdict:** the rating needs a **seller-rating signal** (aggregate, backend +
  spec field) that doesn't exist → **DEFER (backend)**. Not a UI-only fix.

### PD-05 — no installments row → NEEDS-DECISION (Salih) — settled-divergence confirmation
- **Mopro (fact):** the buy box shows the perpetual `_CashbackCard` (D1), no
  installment messaging.
- **Trendyol (provisional):** installment ("taksit") row *(convention)*.
- **Verdict:** installments are a **PSP-hosted / business-model divergence** — the
  audit explicitly asks whether the cashback card is the accepted substitute. That's
  a **product decision for Salih**, not a source/pixel matter. Do **not** build (anti-
  goal: don't re-open the coin/cashback divergence on a guess). **NEEDS-DECISION.**

### PD-06 — gallery: no video, no mobile thumbnail strip → DEFER (video, no data) + NEEDS-DECISION (mobile thumbs)
- **Mopro (fact):** mobile `PdpImageGallery` = `PageView` + dots + tap-fullscreen +
  Hero; desktop `PdpImagePager` = **thumbnail strip + arrows + hover-zoom 2× lens**.
  PD-06 read-path (flat `Product` + variant `image_urls`) already RESOLVED.
- **Trendyol (provisional):** carousel + thumbnails + zoom + **video** *(convention)*.
- **Verdict:** **video** needs a video asset/field that doesn't exist → **DEFER (no
  data)**. A **mobile thumbnail strip** is a UX choice — mobile already has
  PageView + dots (a standard mobile gallery idiom); whether to add a thumb strip on
  small screens is a **NEEDS-DECISION** (and exact feel = NEEDS-VISUAL), not a clear
  gap. Flagged.

### PD-09 — desktop buy-box not pinned → NEEDS-DECISION / NEEDS-VISUAL (conflicts with the deliberate gallery-sticky design)
- **Mopro (fact):** the desktop layout deliberately makes the **gallery column
  sticky-translate** (it measures the buy-box height so the gallery translates within
  the taller column — `product_detail_screen.dart:299-366`); the buy-box itself is
  not pinned.
- **Trendyol (provisional):** desktop buy-box is sticky *(convention)*.
- **Verdict:** Mopro made an **intentional** opposite choice (sticky gallery, not
  sticky buy-box). Pinning the buy-box instead is a **layout redesign** whose
  correctness is a UX/visual judgment (which element should track the scroll) →
  **NEEDS-DECISION** (with NEEDS-VISUAL feel). Not a clean source fix; not guessed.

### PD-10 — recently-viewed not on the PDP → NEEDS-DECISION (placement)
- **Mopro (fact):** recently-viewed is a **home rail**; the PDP has
  `_SimilarProductsRail` + a co-view related rail + Q&A.
- **Trendyol (provisional):** PDP carries a recently-viewed rail too *(convention)*.
- **Verdict:** the data + rail exist; whether to **also** mount recently-viewed on
  the PDP is a **placement decision** (LOW) → **NEEDS-DECISION (Salih)**.

## Outcome

| Row | Verdict |
|---|---|
| PD-02 variant swatches | CONFIRMED → **DEFER** (colour-attribute data; PLP-13 Ph2) |
| PD-03 Sepette %X on PDP | **DEFER** (spec/codegen + backend; *not* display-only — audit stale) |
| PD-04 seller rating | **DEFER** (backend seller-rating signal) |
| PD-05 installments | **NEEDS-DECISION** (cashback substitute? — divergence) |
| PD-06 video / mobile thumbs | **DEFER** (video, no data) + **NEEDS-DECISION** (mobile thumbs) |
| PD-09 desktop sticky buy-box | **NEEDS-DECISION / NEEDS-VISUAL** (conflicts w/ sticky-gallery) |
| PD-10 recently-viewed on PDP | **NEEDS-DECISION** (placement) |

**Zero CONFIRMED UI-only fixes this pass** — the gaps need codegen/backend (PD-03/04),
a colour-attribute model (PD-02), or are product/IA/visual decisions (PD-05/06/09/10).
Many PDP rows were **already closed pre-pass** (PD-01 specs, PD-06 read-path, PD-07
review metadata, PLP-17 official badge). **Discovery shift:** PD-03 is *not*
display-only (the flat `Product` lacks the field).

## Salih's residue (PDP)
- **NEEDS-DECISION:** PD-05 (installments vs cashback card), PD-06 (mobile thumb
  strip), PD-09 (sticky buy-box vs sticky gallery), PD-10 (recently-viewed on PDP).
- **DEFER (engineering, tracked):** PD-02 (PLP-13 Ph2), PD-03 (codegen+backend),
  PD-04 (seller-rating backend).

# PDP-strikethrough — surface variant.original_price_minor to the buy-box

> Closes PR #94's noted follow-up: the PDP buy-box gates the lowest-30d line on
> `lowest_30d < price` only, vs the card's `hasDiscount && lowest_30d < price`, because the mobile
> `Variant` model lacks `original_price`. The DB column exists (0065); it just isn't on the PDP
> through-line. Paths: `internal/catalog/` + `mobile/lib/features/catalog/`.

## 1. Exact state (what's already done vs missing)

`catalog_schema.variants.original_price_minor` exists (migration 0065) and **already flows to the CARD** —
`productSummarySelect` + `ListProductsByIDs` select `v.original_price_minor` → `ProductSummary.OriginalPriceMinor`
→ the card's discount pill (PR #88/#89). But the **PDP path is a different query**: `GetByID → loadVariants →
[]Variant`, and:

| Layer | original_price_minor? | lowest_30d (for reference) |
|---|---|---|
| DB `variants` | ✅ (0065) | ✅ (history) |
| Go `loadVariants` SELECT + domain `Variant` | ❌ **missing** | ✅ (#94) |
| spec `Variant` schema | ❌ **missing** | ✅ (#94) |
| mobile `Variant` model | ❌ **missing** | ✅ (#94) |
| `PdpPriceBlock` widget | ✅ **already renders** strikethrough + `_hasDiscount` + discount pill (built in #94, never fed) | ✅ |
| PDP screen `PdpPriceBlock(...)` calls | ❌ doesn't pass it | ✅ passes `lowest30dPriceMinor` |

So the widget is built; only the **data through-line + the screen pass** are missing. (Discovery-shift vs the
prompt: the strikethrough rendering already exists — this PR feeds it.)

## 2. Changes

1. **Backend** (`internal/catalog`): add `OriginalPriceMinor *int64` (`omitempty`) to the domain `Variant`;
   add `original_price_minor` to the `loadVariants` SELECT + scan. It auto-serializes on the detail response
   via the existing `variantOut` embed (no handler change), exactly like `lowest_30d` in #94. `GetVariantByID`
   (cart) is untouched → leaves it nil (fine; omitempty). No migration (column exists).
2. **Spec + clients**: add `original_price_minor` (nullable int64) to the spec `Variant` schema; regen Go +
   Dart (+ build_runner). Mobile fake-blast-radius: an optional MODEL field doesn't break fakes (PR #85/#88).
3. **Mobile PDP** (`product_detail_screen.dart`): pass `originalPriceMinor: v.originalPriceMinor` (and
   `selectedVariant!.originalPriceMinor`) to the two `PdpPriceBlock` calls — feeds the existing strikethrough.
4. **Gate alignment** (`pdp_price_block.dart`): the lowest-30d line currently shows on `lowest_30d < price`;
   add `_hasDiscount &&` so it matches the card's `hasDiscount && lowest_30d < price`. Now that the PDP has
   `originalPriceMinor`, `_hasDiscount` is meaningful. (Updates the #94 lowest-30d widget test, which passed
   no `originalPriceMinor`.)

## 3. Goldens — 0 flips

The PDP golden fixtures (`pdp_goldens_test._v`, `pdp_screen_composition_test._v`) set **only `priceMinor`**
(no `originalPriceMinor`) → `_hasDiscount` stays false → no strikethrough → goldens unchanged. Unlike
`lowest_30d` (dormant until prices change), the strikethrough is driven by a **static** seed value, so it
*would* render for any product seeded with `original_price > price` — but no test fixture carries that, so 0
flips here. (Real seeded-discount products will show it in the app — the intended effect.)

## 4. Edge cases

- No `original_price` → nil → no strikethrough, no discount pill. (Most variants today.)
- `original_price == price` → `_hasDiscount` false (`>` not `>=`) → no strikethrough. ✓ (existing widget logic)
- `original_price < price` (data error) → `_hasDiscount` false → no strikethrough (defensive; existing logic).
- `lowest_30d == price` (the common case) → no lowest-30d line regardless; strikethrough still shows from
  `original_price` independently.

## 5. Out of scope

DB migration (column exists); price-update logic (P-032); lowest_30d *display* mechanics (PR #93/#94 — only
the gate predicate aligns); card display (#88); buy-box redesign; new tokens.

## 6. Commit plan

1. this doc.
2. backend: `Variant.OriginalPriceMinor` + `loadVariants` SELECT/scan.
3. spec `Variant.original_price_minor` + regen clients.
4. mobile: PDP screen passes `originalPriceMinor` + `PdpPriceBlock` lowest-30d gate `_hasDiscount &&`.
5. tests: backend (GetByID variant carries original_price) + widget (strikethrough show/hide already covered; add the gate-alignment cases) + update the #94 lowest-30d test.
6. docs closure — audit (PDP-strikethrough RESOLVED), ROADMAP, REPORT.

# Cart UI cheap-wins (CT-01/04/05/10) — discovery

> Render-and-UX fixes on existing cart data. No codegen. Verified on
> `feat/cart-ui-fixes`.

## What the cart response carries (the UI-vs-backend decider)

`CartLineDto.fromJson` → `id, product_id, variant_id, seller_id, title,
price_minor, qty, cover_image_url, reserved_until`. `CartDto` →
`lines, totalsBySeller (sellerId, itemsMinor, shippingMinor, totalMinor),
grandTotalMinor, kdvIncludedMinor, isAboveTotalLimit`.

- **Seller NAME — absent** (only `seller_id`). No client-side `seller_id → name`
  lookup exists (`internal/seller` has only `userIsSellerProvider`; the dashboard
  uses the *current* user's `sellerName`). → **CT-01-name = flag backend.**
- **Variant LABEL — absent** (only `variant_id`; no colour/size string). →
  **CT-05-label = flag backend.**
- **Per-seller subtotal — present** (`totalsBySeller.itemsMinor`). → CT-01 UI ✅.
- **Subtotal/shipping — present** (`totalsBySeller` fold; desktop already shows
  it). → CT-04 UI ✅.

## Reuse points

- **Move-to-favorites:** `favoritesProvider.toggle(productId)` +
  `isFavoriteProvider(productId)` (read-only use — favorites lane owns the file).
  Guard with `isFavorite` so it *adds* (never un-favorites). + `removeLine`.
- **Undo (CT-10):** the cart provider exposes `addItem(productId, variantId, qty)`
  — the removed line has all three → re-add restores it.
- **Save-for-later (CT-05):** **no saved-items list exists** anywhere → needs a
  backend list → **flag**; ship move-to-favorites as the available action.

## i18n

Reuse `cart.subtotal` / `cart.shipping` / `cart.shipping_free` (CT-04, CT-01) and
`product.add_to_favorites` (CT-05 tooltip). Only **`common.undo`** is missing —
add it (both locales) for the CT-10 action. (i18n stays 0 dead / 0 missing.)

## Scope split

| CT | UI (this PR) | Flagged backend |
|---|---|---|
| **CT-01** | per-seller **subtotal** in the group header | seller **name** (only `seller_id`) |
| **CT-04** | mobile subtotal/shipping breakdown | — |
| **CT-05** | **move-to-favorites** action | variant **label**; **save-for-later** list |
| **CT-10** | real **Undo** (re-add) | — |

## Plan (commits)

1. discovery. 2. CT-04 mobile breakdown. 3. CT-01 per-seller subtotal header.
4. CT-05 move-to-favorites + CT-10 Undo. 5. test + audit/ledger.
Owned files only: `cart/presentation/cart_screen.dart`, `cart/widgets/
cart_line_card.dart`, `cart/widgets/cart_totals_summary.dart` (+ `common.undo`).
`SectionDivider` (shared) left untouched — the per-seller header is built inline.

# Cart read-path enrichment (the keystone) — discovery

> Make `GET /cart` return the enriched `CartDto` the mobile already parses, so the
> authed cart (and the checkout review, which reads the same `cart.lines`) renders
> live. §5-safe carriers, no codegen (cart is hand-written raw-Dio). Builds on the
> #175 finding (`docs/internal/cart-line-metadata.md`).

## True backend state today

- **`GET /cart` (`cmd/core-svc/main.go` `handleGetCart` → `cart.Service.GetCart`)
  returns raw** `{user_id, items:[{variant_id, qty}]}` (`cart.CartItem` =
  `{VariantID, Qty}`). No enrichment anywhere.
- **The mobile expects** (`CartDto.fromJson`): `{id, user_id, lines:[CartLineDto],
  totals_by_seller:[SellerTotalDto], grand_total_minor, kdv_included_minor}`.
  - `CartLineDto`: `id`(String), `product_id`, `variant_id`, `seller_id`, `title`,
    `price_minor`, `qty`, `cover_image_url?` — **+ to add: `seller_name`,
    `variant_label`** (CT-01/CT-05).
  - `SellerTotalDto`: `seller_id`, `items_minor`, `shipping_minor`, `total_minor`.
- **Line id == variant_id** (DELETE `/cart/items/{variant_id}`; mobile
  `removeLine(lineId)` → `/cart/items/$lineId`). So enriched `id = str(variant_id)`.
- **Checkout review** (`CheckoutReviewScreen`) reads `cart.lines` + `grandTotalMinor`
  — so enriching the cart **inherits CHK-01 (breakdown) + CHK-02 (per-seller
  grouping)** for free (the #174 audit's "review shows total only" is because the
  cart it reads is empty). `POST /checkout/initiate` (order svc) is the submit path,
  separate from the review display.
- **Guest cart** is client-side (`guestCartProvider`, SharedPreferences); `GET /cart`
  is `requireAuth` → guests never hit it. **This change touches only the authed
  backend + handler — the guest path is untouched** (anti-goal §7.3 respected).

## §5-safe carriers (no cross-schema JOIN — all in-process, merged in `cmd/core-svc`)

Per cart item `variant_id`:
1. `catalog.Service.GetVariantByID(variant_id)` → **`Variant`** (rich:
   `SellerID, ProductID, CategoryID, Color, Size, PriceMinor, PriceCurrency,
   ImageKeys`). Gives price, **variant_label** (`Color`/`Size`), seller_id, image.
2. distinct `ProductID`s → `catalog.Service.ListProductsByIDs(ids, locale, market)`
   → `title` + `CoverImageKey` per product.
3. distinct `SellerID`s → **new `seller.Service.SellerNamesByIDs(ids) map[int64]string`**
   (mirror PLP-17 `OfficialSellerIDs` — one `seller_schema` query). Gives
   **seller_name** (CT-01).
4. distinct `CategoryID`s → `catalog.Service.GetCommissionForCategory(market, cat)`
   → `KdvPctBps` for `kdv_included_minor`.

The merge lives in `cmd/core-svc/handleGetCart` (legally uses `cart`+`catalog`+
`seller` Services); **`internal/cart` never imports catalog/seller** → boundary-safe.

## Totals

- `items_minor[seller]` = Σ `variant.PriceMinor × qty` for the seller's lines.
- `shipping_minor` = **0** (v1: cargo handled separately per CLAUDE.md §2.3/§4.8).
- `total_minor[seller]` = items + shipping; `grand_total_minor` = Σ seller totals.
- `kdv_included_minor` = Σ line `round(lineTotal × kdvPctBps / (10000+kdvPctBps))`
  — the KDV **portion of the KDV-inclusive consumer price** ("Fiyatlara KDV
  dahildir"). **Assumption documented**: prices are KDV-inclusive; if the intended
  semantic is commission-KDV (CLAUDE.md §4.8), it's a 1-line follow-up. Not the
  blocker — the cart renders on lines + grand_total regardless.

## Staging (per mission §1.3)

- **PR 1 (this — the bug fix):** enriched lines (incl. `seller_name` + `variant_label`)
  + `totals_by_seller` + `grand_total` + `kdv_included` → authed cart renders;
  checkout review inherits CHK-01/02. UI: seller name in `_SellerGroupHeader`,
  variant label on `CartLineCard`. Contract test for the enriched shape.
- **PR 2:** basket-discount (CT-09/CHK-05) + free-shipping progress (CT-02/CHK-06)
  surfacing.
- **PR 3 (if it balloons):** coupon apply/validate (CT-03/CHK-04) — a feature; split.

No codegen (cart hand-written). Save-for-later / delivery-slots / coin-redeem are out.

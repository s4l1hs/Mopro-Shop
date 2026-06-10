# Cart line metadata (CT-01 seller name / CT-05 variant label) — discovery + DEFER

> **Verdict: DEFER.** The premise ("the cart line carries only `sellerId`/`variantId`,
> just add seller name + variant label") does not match the backend. The enriched
> cart line **does not exist server-side at all** — `GET /cart` returns raw items.
> CT-01/CT-05 are gated on building the whole cart read-path enrichment, which
> necessarily includes the totals cluster the metadata lane deferred. Documented
> here so a correctly-scoped lane can build it; **no half-built code shipped.**

## The finding (the cart read-path is a backend stub)

- **`GET /cart` returns the minimal domain `cart.Cart`** (`cmd/core-svc/main.go`
  `handleGetCart` → `cart.Service.GetCart`): `{user_id, items:[{variant_id, qty}]}`.
  `cart.CartItem` (`internal/cart/domain.go`) is **`{VariantID, Qty}` only** — no
  seller, no price, no title, no variant attributes. `GetCart` does `repo.GetItems`
  and returns them unenriched (`internal/cart/service.go`).
- **The backend never serializes** `lines`, `seller_id`, `title`, `price_minor`,
  `cover_image_url`, `totals_by_seller`, `grand_total_minor`, or `kdv_included_minor`
  for the cart (grep across `cmd/core-svc` + `internal/cart`: zero hits outside
  catalog).
- **The mobile expects a fully-enriched response.** `CartDto.fromJson`
  (`mobile/lib/features/cart/data/cart_dto.dart`) reads `json['lines']`,
  `json['totals_by_seller']`, `json['grand_total_minor']`, `json['kdv_included_minor']`;
  `CartLineDto` requires `id, product_id, variant_id, seller_id, title, price_minor,
  qty, cover_image_url`. `cart_provider._load` just calls `repo.getCart()` — **no
  client-side enrichment** (no `/products/batch` fallback like favorites).
- **Consequence:** against today's backend, `json['lines']` is absent →
  `CartDto.lines == []` → **the authed cart always renders empty.** The entire
  `CartDto`/`CartLineDto`/`totalsBySeller` layer is client-anticipated but
  backend-unfulfilled.

## Why CT-01/CT-05 can't be done as "two fields"

- **CT-01 (seller name in `_SellerGroupHeader`)** — the header renders
  `'#$sellerId'`. There is no served line to carry a `seller_name`, and
  `totalsBySeller` (the per-seller subtotal the cart audit marked "UI ✅") is also
  never emitted, so the subtotal renders 0/empty too.
- **CT-05 (variant label on the line)** — needs the variant's colour/size; the
  cart never resolves `variant_id` → variant, and `ProductSummary` (the only
  batch-enrichment source available client-side) is **product-level** (no
  variant), so the label isn't obtainable on either path without new resolution.
- Both therefore require **building the cart read-path enrichment first**:
  resolve `items → variants → products → sellers`, group by seller, compute
  per-seller subtotals + KDV + grand total, and serialize the rich `CartDto`. That
  read-path **must** include `totals_by_seller` + `grand_total_minor` +
  `kdv_included_minor` (the mobile `CartDto` demands them) — i.e. it absorbs the
  **totals/checkout cluster** the metadata lane explicitly deferred (CT-04 etc.).

## Recommended next lane (correctly scoped) — "cart read-path enrichment"

A single backend lane that makes `GET /cart` (and the `POST /cart/items`/merge
responses) emit the rich `CartDto` the mobile already parses:

1. **Enrich server-side, §5-safe** (mirror PLP-17's app-merge — the merge lives in
   `cmd/core-svc`, never `internal/catalog` importing `seller`):
   - `variant_id → catalog.Variant` (`catalog.Service.GetVariantByID`, exists) for
     **price, colour/size (CT-05 label), product_id, stock**.
   - `product_id → catalog` for **title, cover image, seller_id**.
   - distinct `seller_id`s → a **seller-name batch carrier** (add
     `seller.Service.SellerNamesByIDs(ids) map[int64]string`, mirroring the
     PLP-17 `OfficialSellerIDs` batch) for **CT-01 seller name**.
2. **Group + totals:** per-seller subtotal + KDV + grand total + cashback line
   (the deferred CT-04 cluster — unavoidable here).
3. **No spec/codegen for the cart:** the cart endpoints are **hand-written
   raw-Dio**, NOT in `api/openapi.yaml` (like favorites/reviews) — see
   [[project-favorites-arch]]. Guard with a **live-handler contract test**
   asserting the rich shape, not a spec schema.
4. UI: replace `'#$sellerId'` with the served `seller_name`; render the variant
   label on `CartLineCard`. (The UI widgets already exist — they just need real data.)

**Out of scope even then:** save-for-later (a saved-items store — separate),
coupon, basket-discount, warnings, recommendations.

## What this lane did

Docs-only (per the user's "document + defer" decision): this finding + a corrected
`TRENDYOL_PARITY_CART_AUDIT.md` (CT-01/CT-05 + the `totalsBySeller` "UI ✅" claim
re-framed as gated on the unbuilt enrichment) + ledger. No code changed.

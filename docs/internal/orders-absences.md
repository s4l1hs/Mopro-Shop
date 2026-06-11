# Orders absences bundle — OR-02 / OR-05 / OR-07 (discovery)

Read-path check of the three Orders gaps **before** building (the cart-stub lesson).
Outcome: **OR-05 + OR-07 ship; OR-02 DEFERs** (deeper than audited — the data isn't
captured on the order). Two of three were not the "cheap surfacing" the audit framed.

## OR-07 — per-order help entry — ✅ cheap (ship)

- A real `/help` route (`HelpIndexScreen`) exists (same target AC-02 wired). The order
  detail has no help entry. **Fix:** a "Yardım" button on the order detail →
  `context.push('/help')`. One widget. Cheapness CONFIRMED.

## OR-05 — variant label on order line items — 🔁 deeper, but in-scope (ship)

**Discovery shift — the order-item read-path is a STUB, not just a missing label.**
`GET /orders/{id}` (`handleGetOrder`) serializes the **raw** `order.OrderItem`, which
carries only `variant_id` / `unit_price_minor` — **no `title`, no `price_minor`, no
`cover_image_url`, no variant label**. But the mobile `OrderItemDto.fromJson` *requires*
`json['title']` and `json['price_minor']` (no fallback), so order-detail items don't
render against the real backend at all. This is the **same pre-enrichment gap the cart
had** (the audit said exactly this) — the variant label sits on top of an item
enrichment that was never built.

- **Fix (the §5 variant carrier, #176 pattern):** enrich order items server-side in
  `handleGetOrder` via the catalog `Service` carrier — `GetVariantByID` (variant
  colour/size → `variantLabel`, cover, product_id) + `ListProductsByIDs` (locale title,
  cover fallback). Emit per item: `id, order_id, product_id, variant_id, title,
  variant_label, price_minor (= unit_price_minor), qty, commission_pct_bps,
  cover_image_url`. §5-safe (catalog `Service`, no cross-schema JOIN); mirrors
  `cart_enrich.go` and reuses its `variantLabel(v)` helper.
- **Mobile:** `OrderItemDto.variantLabel` (+ parse `variant_label`); the line renders
  the label under the title (like the cart line). This both **adds the label (OR-05)**
  and **fixes the latent items-don't-render stub**.
- Cheapness: MODERATE — the lane explicitly scopes "a §5 variant carrier / #176
  pattern", so this is in-scope, just bigger than the word "cheap" implied.

## OR-02 — delivery address on the order — 🚩 DEFER (deeper than audited)

**Discovery shift — the order does NOT carry a delivery address.** Confirmed:
`order_schema.orders` has **no address columns**, `order.Order` has **no address
field**, and `InitiateCheckoutRequest` takes **no address**. The mobile checkout *does*
select an `Address` (`checkout_address_screen` / `checkout_controller.selectedAddress`),
but it's used **only to derive the PSP buyer name** (`address.name`) — it is never sent
to or stored on the order. So there is **nothing to surface**; this is an **A** (absent
data), not a stub-over-data.

- **Why not in this lane:** an honest fix is a **checkout-capture vertical**, not a
  display add, and it crosses into the checkout/payment path (the lane is "Orders UI +
  a §5 variant carrier — not returns/refund"). Per §1.3, DEFER + flag rather than
  balloon scope.
- **Precise plan (separate lane):**
  1. `InitiateCheckoutRequest` gains an address **snapshot** (street/city/district/zip/
     name/phone — a snapshot, not an `address_id` FK, since identity addresses can be
     edited/deleted after the order; soft-ref the id for provenance only).
  2. `order_schema.orders` migration: address snapshot columns (or a JSONB
     `delivery_address`); the saga writes them at order creation.
  3. `handleGetOrder` surfaces the snapshot; `OrderDto.deliveryAddress` parses it; the
     order detail renders an address card.
  4. Mobile checkout sends the selected address in the initiate body.
  Touches checkout + order + schema + mobile (≈6 files) — a vertical, not a surfacing.

## Summary

| Gap | Audited as | Read-path reality | Verdict |
|---|---|---|---|
| OR-07 help | A | real `/help` route; no order entry | ship (cheap) |
| OR-05 variant label | A (pre-enrichment gap) | items served **raw** (no title/price/label) — a stub | ship (build the §5 carrier) |
| OR-02 address | A | **not captured** on the order at all | **DEFER** (checkout-capture vertical) |
</content>

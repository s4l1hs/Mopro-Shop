# PLP-17 / PD-04 — official-seller badge (discovery)

> Trendyol "Resmi satıcı rozeti" on the PLP product card (PLP-17) + the PDP seller
> card (PD-04). The flag lives in `seller_schema`; the card/product is `catalog` —
> so the **§5 cross-schema constraint is the crux** (no JOIN). Resolved via
> in-process `seller.Service` calls + a handler app-merge (the established P-029
> pattern), never a SQL JOIN.

## State found

- **No official/verified flag on sellers.** (`grep verified` only hits identity/OTP.)
  `seller_schema.sellers` (migration **0078**) carries id/slug/display_name/…/
  status/created_at. → **add `is_official BOOLEAN NOT NULL DEFAULT FALSE`** + seed
  a few official sellers (business data → seed, per §7.2).
- `seller.Seller` (domain) + `sellerCols` (repo `GetByID`/`GetBySlug`) — add
  `IsOfficial`.

## §5-safe carriers (no cross-schema JOIN)

- **PDP (PD-04) — carrier A already exists.** `handleGetProductDetail`
  (`cmd/core-svc/catalog_handlers.go`) already resolves the seller in-process via
  `sellerSvc.GetByID(p.SellerID)` → `seller_name`/`seller_slug`. Add `IsOfficial`
  to `Seller`, emit `seller_official` on the flat `Product` response, render on
  `PdpSellerCard`. Trivial.
- **PLP card (PLP-17) — carrier B (add an app-merge).** `ProductSummaryRow` carries
  `SellerID` but the card has **no** per-product seller carrier today (the
  `is_bestseller`/`basket_discount_pct` card badges are denormalized **product**
  columns, not seller data). A SQL JOIN to `seller_schema` is **forbidden (§5)**.
  Add **`seller.Service.OfficialSellerIDs(ctx, ids []int64) (map[int64]bool, error)`**
  (one `seller_schema.sellers WHERE id = ANY($1) AND is_official` query — §5-safe,
  single schema) and **app-merge in the handler**: `handleListProducts` /
  `handleSearch` collect the page's distinct `SellerID`s, call `OfficialSellerIDs`,
  and set `ProductSummaryRow.IsOfficialSeller` per row before
  `buildProductListResponse`. **Boundary-safe:** the merge is in `cmd/core-svc`
  (package main, which legally uses both `catalog.Service` + `seller.Service`);
  `internal/catalog` never imports `seller`. Mirrors the P-029 bestseller-by-IDs
  app-merge. Wire `sellerSvc` into both handlers (`main.go`).

## Spec + codegen

- `ProductSummary.is_official_seller` (bool) — card badge.
- `Product.seller_official` (bool) — PDP seller card (alongside `seller_name`/
  `seller_slug`). `make api-gen` Go + Dart regen; the **drift + live-handler
  contract test** (now required) cover the new fields.

## UI

- `product_card.dart` — a small "Resmi Satıcı" badge/check when `isOfficialSeller`.
- `pdp_seller_card.dart` — a verified check next to the seller name when
  `sellerOfficial`.

## Plan (commit per concern)

1. Migration: `is_official` on `seller_schema.sellers` + seed a few official sellers
   (dev seed for the walk). `Seller.IsOfficial` + `sellerCols`/scan.
2. `seller.Service.OfficialSellerIDs` (batch) + repo impl; `Seller.IsOfficial` via
   `GetByID` (PDP).
3. Catalog/handler: `ProductSummaryRow.IsOfficialSeller` (handler-set, app-merge);
   `Product.seller_official` on the detail response; wire `sellerSvc` into list/search.
4. Spec + Go/Dart codegen (+ the API-fake fan-out).
5. UI: product-card + PDP-seller-card badges. i18n.
6. Tests: integration (official flag surfacing) + extend the live-handler contract
   test; widget tests; audits (PLP-17, PD-04) + ledger.

§5 split-bailout: if heavy, ship the flag + carriers + codegen first, the badge UI
second. Never JOIN across schemas.

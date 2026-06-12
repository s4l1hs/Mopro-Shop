# Favorites UX — FAV-05 add-to-cart + FAV-06 sort/filter (discovery)

Lane A3 (`feat/favorites-ux`). Closes the two deferred favorites rows from
`docs/internal/favorites-probable-resolution.md` / `TRENDYOL_PARITY_FAVORITES_AUDIT.md`.

## What exists (facts)

- **Favorites store IDs only.** `favorites_provider.dart` holds a `Set<int>` of
  product IDs in SharedPreferences (+ FAV-02 server down-sync union). No variant,
  no price snapshot.
- **The screen batch-fetches `ProductSummary`s** via `POST /products/batch`
  (`cmd/core-svc/home_handlers.go:handleProductsBatch`) and renders the shared
  `ProductCard` in a 2/4/5 responsive grid. `ProductSummary` carries **no
  variant id** — `price_minor` is "lowest-priced active variant".
- **Cart add needs `product_id + variant_id + qty`** (`CartNotifier.addItem` →
  `POST /cart/items`; emits the `add_to_cart` analytics event itself).
- **The PDP read path already resolves variants:** `GET /products/{id}`
  (generated `CatalogApi.getProduct`, used by `productDetailProvider`) returns
  `Product.variants: List<Variant>` with per-variant `stock`. This endpoint is
  already §5-clean — no new backend carrier is needed.

## FAV-05 decision — client-side resolution, NO codegen, NO backend change

The audit flagged two traps: (a) favorites hold only product IDs, (b) adding the
button to the **shared** `ProductCard` serializes with the PLP/PDP lanes (§3).
Both are avoided:

- **Variant resolution is client-side** on tap: fetch `GET /products/{id}`
  (the existing PDP read path — the §5-safe "carrier" is the endpoint that
  already exists; nothing new server-side, nothing in the OpenAPI spec →
  **codegen NOT needed**, the lighter path per §1.3).
- **Resolution rule** over `variants.where(stock > 0)`:
  - **0 in-stock** → snackbar `favorites.out_of_stock`, no add (graceful OOS).
  - **exactly 1 in-stock** → direct `cartProvider.addItem(qty: 1)` + the
    standard `cart.added_to_cart` snackbar with a go-to-cart action (same UX as
    the PDP). This also covers multi-variant products where only one variant is
    purchasable — the choice is forced anyway.
  - **>1 in-stock** → the user must choose (size/colour) — **route to the PDP**
    (`/products/{id}`) with a `favorites.select_options` hint snackbar. Silently
    picking "first in-stock" risks adding the wrong size; a quick-add sheet is a
    heavier feature than this lane warrants (future polish).
- **The button lives in the favorites screen only**: a screen-local `_FavCard`
  wrapper (Column: `ProductCard` + full-width "Sepete Ekle" button) — the shared
  `ProductCard` widget is **untouched**. Grid `childAspectRatio` is adjusted
  locally to make room. Per-card in-flight state disables the button + shows a
  spinner while resolving/adding.

## FAV-06 decision — client-side over the fetched list (no backend)

- **Sort** (popup menu on a toolbar row above the grid): default (fetch order) /
  price ascending / price descending / discount % descending. Labels reuse
  `catalog.sort_title`, `catalog.sort_price_asc`, `catalog.sort_price_desc`;
  new `favorites.sort_default`, `favorites.sort_discount`.
- **Filter** (toggle chips on the same row): **discounted** (`discount_pct > 0`,
  new `favorites.filter_discounted`) and **free shipping** (`free_shipping`,
  reuses `plp.free_shipping`). In-stock is not filterable — `ProductSummary`
  has no stock signal (consistent with FAV-07's "IDs only" residue).
- Filters that empty the list render a centered `favorites.filter_empty` hint
  (the favorites themselves are intact — distinct from the true empty state).
- State is screen-local autoDispose `StateProvider`s — resets on leave, no
  persistence (lean surface; parity with the audit's LOW rating).

## i18n

New keys (all four locales — `i18n-check --strict`): `favorites.out_of_stock`,
`favorites.select_options`, `favorites.sort_default`, `favorites.sort_discount`,
`favorites.filter_discounted`, `favorites.filter_empty`. Everything else reuses
existing keys (`product.add_to_cart`, `cart.added_to_cart`, `cart.add_failed`,
`nav.cart`, `catalog.sort_title`, `catalog.sort_price_asc/desc`,
`plp.free_shipping`).

## Tests / goldens

- Widget tests extend the existing `_BatchAdapter` harness to also serve
  `GET /products/{id}` + `POST /cart/items`: OOS path, single-variant direct-add
  path, multi-variant→PDP path; sort + filter reorder/prune the grid.
- The favorites desktop goldens **flip** (new toolbar + per-card button) —
  Linux-baselined, regenerated via the golden-rebaseline workflow (goldens job
  is informational/non-required per the gate design).

## Discovery shifts (vs the lane prompt)

1. **No §5 carrier had to be built** — the prompt anticipated a catalog carrier
   à la cart #176, but the PDP's `GET /products/{id}` already serves variants
   with stock; FAV-05 is purely a mobile change.
2. **Codegen: NO** — no spec change, so this lane's codegen ownership goes
   unused.
3. **Multi-variant → PDP redirect** (not auto-pick, not quick-add sheet):
   correctness over convenience for sized goods; sheet is future polish.
4. The audit's §3 serialization trap (shared `ProductCard`) is dodged with a
   favorites-local wrapper — zero shared-widget diff.

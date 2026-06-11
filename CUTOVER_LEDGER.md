# CUTOVER_LEDGER.md

> Single source of truth for everything parked while production deploys are deferred (Phase B + C). Nothing here is lost; every item must be reconciled at the eventual cutover. Last updated: 2026-06-08.

---

## 0. Headline state

- **Production is still on the 2026-05-26 build.** Everything from #105 onward is merged to `main` but **not live** (deploys deliberately deferred until after Phase B+C).
- All deploy machinery is fixed and staged; the cutover is a known, rehearsed sequence — see §1.

---

## 1. Deferred production deploy (the staged runway)

**Trigger:** when Phase B+C are done, execute DEPLOY-EXEC-01 (host-prep → backup → dry-run → migrations → deploy → health → purge).

| Step | Detail |
|---|---|
| Host-prep | Add `GHCR_USER` + `GHCR_PAT` (read:packages) to `/etc/mopro/.env` (via the `/opt/mopro/deploy/.env` symlink). |
| Backup | `pg_dump -Fc` ecom + ledger before migrating (tiny DBs). The §3-era backups are stale — re-take fresh at cutover. |
| Dry-run | Dispatch deploy `verify_only=true` (login-only; proves GHCR auth). |
| Migrations | `apply-migration.sh --db ecom up` then `--db ledger up`. Count is large now (ecom 62→0088+, ledger 77→0081) — apply, then deploy promptly (tight window). |
| Deploy | Dispatch `verify_only=false`; #105 fail-fast + image-ID assertion guards a no-op. |
| Health | Re-run the #104 diagnosis; expect GREEN + smoke 5/5. |
| Post-flip purge | RUNBOOK "Post-flip cleanup": stale `mopro/*` images + `bin/*.tar` tarballs (gated on prod confirmed on `ghcr.io/s4l1hs/*`). |

**Rollback (if deploy fails after migrations):** ecom image-only; **ledger leads with `pg_restore`** of the pre-migration dump (0078.down is suspect), `ledger down` secondary. Data covered by the §backup dumps.

---

## 2. TLS / ACME — the Aug-18 hard clock ⏰

- Production TLS cert **hard-expires 2026-08-18**; Caddy auto-renew attempt ~**Jul 19**.
- The #106 ACME resolver fix is **merged but not live** (deploy deferred) → renewal will still SERVFAIL until a deploy lands it.
- **Backstop schedule:** `mopro-cert-renewal-backstop` (Sundays in Jul/Aug, gated 2026-07-19 → 08-17) — reminds + emits an on-host check-prompt.
- **Decision required before ~Jul 19** (one of):
  1. Deploy before the window (lands #106 — cleanest).
  2. One-off host hotfix: add resolvers to the host Caddy config + `caddy validate && docker compose -f docker-compose.prod.yml up -d caddy` (recreate, ~2–5s blip; certs persist).
  3. Accept lapse (only if prod isn't serving — it self-heals at the eventual deploy).

---

## 3. F-019 — reconcile grant (live prod defect, fix pending deploy)

- `reconcile_user` lacked `SELECT` on `event_delivery_attempts` → the weekly reconcile cron throws `42501` + the table grows unbounded.
- **Fixed in #111** (ledger migration 0081 `GRANT SELECT` + init/73 converged) — but the fix only takes effect in prod **when ledger migrations apply at cutover**. Until then the live error + slow growth continue (tolerable pre-launch).
- **Resolves automatically at deploy** (§1 ledger migrations).

---

## 4. PLP-12 — subtree rollup — ✅ RESOLVED (`feat/plp-subtree-rollup`)

- ~~`repository.go` scoped products by exact `category_id`~~ → **`ListProductsByCategory` now scopes via a `WITH RECURSIVE` subtree over `ref_schema.categories`** (parent_id walk): a parent aggregates all descendant products, a leaf resolves to itself. §5-safe (ref_schema is the cross-module-readable exception). Migration **0088** + init snapshot add `categories_parent_id_idx`. Integration test (parent→child→grandchild) + live-verified (root-elektronik 0→31, leaf elektr-kea 28).
- **Deploy note:** migration 0088 lands at the §1 cutover (`apply-migration.sh --db ecom up`); the index is additive (`IF NOT EXISTS`).

## 4b. PLP-13 — attribute facets — ✅ PHASE 1 COMPLETE for `renk` (user loop closed)

- **Phase 1, PR 1 (foundation) — landed:** migration **0089** creates the normalized model `attribute_keys` / `category_facets` / `product_attributes` (catalog_schema, §5-safe; aggregation + per-product indexes; fixed `renk` key). The per-product backfill is a **dev seed** `scripts/seed/data/attr-extras.sql` (migrations run pre-seed in dev) — normalizes `variants.color` → `product_attributes(renk)` + enables `category_facets(renk)` wherever colour exists. Migration-safe, idempotent, **live-verified** (product 15 → {Beyaz, Lacivert, Siyah}; category buckets aggregate). In prod the backfill runs as a one-off data step at cutover.
- **PR 2 (read-path) — landed (`feat/plp-13-readpath`):** `GET /categories/{id}/facets` (subtree aggregation — the first facet endpoint) + `attr=<slug>:<value>` filter (PLP + search) + `Product.attributes` + Go/Dart codegen + integration + live-handler contract tests.
- **PR 3 (PDP specs) — landed (`feat/plp-13-pdp-specs`):** the PDP specs tab renders `Product.attributes` (`_SpecsTab`, mobile + desktop; `_StubTab` gone) → **PD-01 resolved for the `renk` slice** + a specs-tab widget test + i18n.
- **PR 4 (FilterPanel accordion) — landed (`feat/plp-13-filterpanel-facet`):** `FilterPanel` renders a server-driven `renk` accordion (`PlpAttributeFacet`, mirror `PlpBrandFacet`, value+count, gated on `currentCategoryId>0` → **search inherits, category-gated**) + `PlpFilters.attrs` (Map<slug,values>) + codec round-trip (`attr_<slug>=…`) + `toggleAttr` + `attributeFacetsProvider` + `filteredProductsProvider` threads `attr` + removable chips. **No new i18n** (facet name/values are server-localized) + a codec/toggle/render test. **Phase-1 user loop is now closed for `renk`** (filter on PLP + search + PDP specs). `depolama`/other attrs + Phase 2/3 deferred per #149. Phase-1 plan: `docs/internal/plp-13-p1.md`; PR-4 discovery: `docs/internal/plp-13-pr4.md`.
- **Phase 2 (more attribute types) — DEFER'd, blocked on a data source (`feat/plp-13-phase2`):** the infra is confirmed **generic** (`FacetsByCategory` walks `category_facets` for any attribute, no renk filter; `PlpAttributeFacet`/PDP-specs render any) → any registered attribute lights up zero-code. **But there is no clean, semantically-correct source for a 2nd type:** `products.specs` JSONB **never existed** (the #149 phase-2 assumption is wrong), and `variants.size` is semantically *size* (not storage/RAM), heterogeneous (apparel `L/M` mixed with dimensions/volumes/mis-filed `256GB`) + sparse (1–2 products/category). Color was the only correct structured attribute → consumed by `renk`. **Real phase 2 = the attribute write-path** (sellers/ingestion populate `product_attributes` with typed values), not a backfill. No code/seed/migration added (empty keys would surface nothing). See `docs/internal/plp-13-p2.md`.
- Protected by the gen-sync drift gate (§5) + the #158 live-handler contract test.

### (original design context — retained)

- Trendyol's deep, **category-aware** attribute stack (storage/RAM/screen/colour/condition/camera…). Mopro has **no normalized attribute/facet model**: only `catalog_schema.variants.color/size` (structured but **not** filter params + sparse) and `catalog_schema.products.specs` (**opaque per-category JSONB**, no facet schema/index). No facet-aggregation (values+counts) surface.
- **Verdict: Outcome C — DEFER** (per the batch discovery). Building JSONB-key faceting on opaque `specs` = a fragile attribute store (anti-goal). The real fix is a **schema/data-modeling track**: a normalized product-attribute model + per-category facet config + an aggregation endpoint (mirror brand/rating) + filter params + accordion UI.
- **Design (Track D) ready:** `docs/internal/plp-13-attribute-model.md` — `attribute_keys` / `category_facets` / `product_attributes` (catalog_schema, §5-safe), a brand/rating-style facet aggregation, accordion UI reusing `PlpBrandFacet`, and a **4-phase plan**. Even Phase 1 (schema + backfill `renk`/`depolama` + one facet + UI) is a full vertical → each phase is its own scoped PR. Build DEFER'd.

---

## 4c. PLP-14 — price-history filter ("Fiyatı düşenler") — ✅ RESOLVED (`feat/catalog-backend-vertical`, PR 2)

- **Built** as the OpenAPI-codegen vertical: `price_dropped` boolean param on `listProducts`+`search` → `ProductFilter.PriceDropped` → §5-safe `EXISTS` over `catalog_schema.variant_price_history` (0083, index-served `vph.price_minor > v.price_minor` within 30d) → `make api-gen` Go+Dart regen → `PlpFilters.priceDropped` + codec (`drop=down`) + `FilterPanel` & `PlpFilterSheet` toggle + removable chip + i18n (`plp.filter_price_dropped`/`plp.filter_price_history`).
- **Tests:** `TestIntegration_PriceDroppedFilter` (backend, fresh-PG), filter-wiring + codec/model round-trips (Dart). 15 generated-client fakes updated for the new method param.
- **Goldens:** `plp_sidebar_*` + `search_sidebar_*` flip (a new sidebar toggle row) — **not regenerated locally** (anti-goal); the Linux golden-rebaseline job rebaselines on the PR. Design: `docs/internal/plp-14-price-history.md`.

## 4d. SE-08 / SE-03 — search relevance + result count — ✅ RESOLVED (`feat/catalog-backend-vertical`, PR 1)

- **SE-08** — `SearchProductsSummary` now ranks by `ts_rank(search_vector, plainto_tsquery('simple', q))` for the default (`recommended`) sort via `appendSearchOrderBy`; explicit sort tokens (price/newest/cashback) and bestseller `PopularIDs` still win. Backend-only — relevance is the implicit default, so **no contract/token change, no codegen**. Reuses the 0057 GIN `search_vector` + the already-bound `$1` query (no new index/placeholder). Integration test `TestIntegration_SearchRelevance`. Discovery: `docs/internal/be-vert.md`.
- **SE-03** — already satisfied: the `Search` 200 envelope returns `pagination.total` (required `PaginationMeta`, populated by `handleSearch`→`buildProductListResponse`). No backend change; the search UI (Session 1) reads it.

## 4e. PD-06 — PDP read-path conformance + contract guard — ✅ RESOLVED (`fix/pdp-readpath-contract`)

- **PD-06** — `GET /products/{id}` returned a legacy `{product, variants, translations, cashback_preview, delivery_eta}` envelope with variant `image_keys`/`cover_image_url`, matching neither the OpenAPI flat `Product` (variants[] = `Variant`, `image_urls` required) nor the generated mobile client (also flat) — so the strict parse failed and the PDP never rendered end-to-end (the walk was blocked). The handler now emits the flat spec `Product`: top-level `id/seller_*/category_id/brand/status/created_at`, locale-resolved `title`/`description` (drops the unused `translations` array), and each `Variant` with **`image_urls`** = `image_keys` mapped through `mediaurl.CDNUrl`. **No codegen** (spec + client already flat).
- **Contract guard (the systemic catch):** the F-021 test (`internal/api`) is fixture-only and never calls a handler — which is why PD-06 shipped. Added a **live-handler conformance test** (`cmd/core-svc/contract_test.go`, `//go:build contract`): calls the real handler, `VisitJSON`s the response against the `Product` schema (+ guards `image_urls` present / no envelope leak). Extended `make contract-test` + `openapi-ci.yml` to run it. Discovery: `docs/internal/pdp-readpath.md`.
- **PD-07 — ✅ RESOLVED (`feat/pd-07-review-metadata`):** reviews now return `reviewerName` (masked `identity.Service.GetMe` → `maskReviewerName`, "A** Y**") + `photoUrls` (`attachments.Service.ListByEntity('review', id)` → `mediaurl.CDNUrl`) — §5-safe in-process service calls via narrow handler interfaces, no cross-schema JOIN; a lookup failure never fails the page. PDP renders a reviewer header + photo-thumbnail strip. **Discovery shift: no codegen** — the reviews endpoint is hand-written (raw-Dio mobile client, not in the OpenAPI spec); the live-handler contract test asserts the fields directly. Remaining review nuance: rating-filter (sort only today).

## 4f. PLP-17 / PD-04 — official-seller badge — ✅ RESOLVED (`feat/plp-17-official-seller`)

- **PLP-17 + PD-04** — Trendyol's "Resmi Satıcı" badge, absent on both the PLP card and the PDP seller card; gated on a non-existent seller flag. Migration **0090** adds `seller_schema.sellers.is_official` (sellers 1,3 seeded official — content data for the walk; 2 stays plain so the difference shows). `Seller.IsOfficial` + `seller.Service.OfficialSellerIDs(ids)` (a single-schema batch lookup).
- **The §5 crux (no cross-schema JOIN).** The flag is `seller_schema`; the card/product is `catalog`. Two §5-safe carriers, both in-process: **PDP (PD-04)** reuses the existing `sellerSvc.GetByID` in `handleGetProductDetail` → `Product.seller_official`. **PLP card (PLP-17)** app-merges in the handler — `handleListProducts`/`handleSearch` collect the page's distinct `SellerID`s, call `OfficialSellerIDs`, and set `ProductSummary.is_official_seller`. The merge lives in `cmd/core-svc` (legally uses both `catalog` + `seller` Services); **`internal/catalog` never imports `seller`** — boundary checker green, no JOIN. Mirrors the P-029 bestseller app-merge.
- **Spec + codegen:** `Product.seller_official` + `ProductSummary.is_official_seller`; Go + Dart regenerated (drift gate green). **Contract test** asserts `seller_official=true` for an official seller; **seller integration test** verifies 0090 + the `OfficialSellerIDs` set (excludes non-official + absent ids). UI: blue "Resmi Satıcı" verified ribbon on the card (top-left stack) + a verified check on `PdpSellerCard`. Discovery: `docs/internal/plp-17.md`.
- **PD-04 is partial:** the official badge is done; the **seller rating** half stays open (no seller-rating aggregate yet).

---

## 4g. FAV-02/03/04 — favorites down-sync + polish — ✅ RESOLVED (`feat/favorites-downsync`)

- **FAV-02** (the substantive favorites gap, from the Favorites parity audit) — favorites were **local-first, sync-up-only**: `POST /favorites/sync` pushed local→server on login, but there was **no read-back**, so the mobile list read `SharedPreferences` only and the server `user_favorites` rows fed just the P-004 count → **no cross-device favorites**. Added **`GET /favorites`** (requireAuth → `{product_ids}`) + mobile **server→local hydration** (`hydrateFavoritesFromServer` → `FavoritesNotifier.mergeServer`, a union), triggered after the up-sync on login **and** fire-and-forget on launch when authed. Sync is now **two-way** → cross-device.
- **§5-safe + testable:** `GET /favorites` is a single `catalog_schema.user_favorites` query behind a narrow `favoritesReader` seam (`pgFavoritesReader{pool}`), so the live-handler **contract test** can stub it (favorites aren't in the OpenAPI spec — hand-written like reviews/PD-07, so **no codegen**; the contract test asserts the shape + empty→`[]`). The up-sync (`mergeGuestFavorites`, in `features/cart/**`) was left untouched.
- **FAV-03** hardcoded `'Temizle'` → `favorites.clear_all`.tr(); **FAV-04** error→infinite-skeleton → a real `_ErrorState` (message + retry). Discovery: `docs/internal/fav-downsync.md`.
- **Still open:** FAV-01 collections (= flagship **P-013**, separate); FAV-05/06/07 await Salih's walk.

---

## 4h. Cart read-path enrichment — 🚩 DISCOVERED + DEFERRED (`feat/cart-line-metadata`, docs-only)

- A "cart line metadata" lane (add CT-01 seller name + CT-05 variant label) opened against a **false premise**: the enriched cart line doesn't exist server-side. **`GET /cart` returns raw `{user_id, items:[{variant_id, qty}]}`** (`handleGetCart` → `cart.Service.GetCart`; `cart.CartItem` = `{VariantID, Qty}` only); the backend never emits `lines`/`seller_id`/`seller_name`/`title`/`price_minor`/`totals_by_seller`/`grand_total_minor`/`kdv_included_minor`. The mobile's `CartDto`/`CartLineDto`/`totalsBySeller` layer is **client-anticipated but backend-unfulfilled** (and `cart_provider._load` does no client enrichment) → **the authed cart renders empty today.**
- So **CT-01, CT-04 (the audit's "RESOLVED" subtotal), and CT-05 are all gated on one backend lane — the cart read-path enrichment** — which *must* include the totals cluster the metadata lane deferred. **User decision: document + defer** (no half-built code). Discovery + the correctly-scoped next lane: `docs/internal/cart-line-metadata.md`; `TRENDYOL_PARITY_CART_AUDIT.md` §1 carries a ⚠ correction + the rows/fix-list re-framed.
- **Next lane (scoped):** enrich `GET /cart` §5-safe (variant→product→seller via catalog `GetVariantByID` + a new `seller.Service.SellerNamesByIDs` batch carrier, mirroring PLP-17's app-merge in `cmd/core-svc`; never `internal/catalog`-imports-seller). Cart isn't in the OpenAPI spec (hand-written, like favorites/reviews) → no codegen; live-handler contract test. Save-for-later/coupon/basket-discount remain separate.

---

## 4i. Cart read-path enrichment — ✅ RESOLVED (`feat/cart-readpath-enrichment` PR 1)

- **The §4h fix, shipped.** `handleGetCart` now enriches the raw cart into the rich `CartDto` the mobile expects — **the authed cart (and the checkout review) render live** (they were empty). `enrichCart` (`cmd/core-svc/cart_enrich.go`) resolves each item §5-safely: `catalog.GetVariantByID` (variant_label colour/size + price + seller_id + product_id + image), `catalog.ListProductsByIDs` (title/cover), the new **`seller.SellerNamesByIDs`** carrier (seller_name, CT-01), `catalog.GetCommissionForCategory` (KDV). Groups by seller → `totals_by_seller` (items/shipping=0/total) + `grand_total_minor` + `kdv_included_minor`.
- **§5 + boundary:** the merge lives in `cmd/core-svc` behind narrow `cartCatalogResolver`/`cartSellerNamer` interfaces; **`internal/cart` imports neither catalog nor seller** → boundary checker green, no JOIN. No codegen (cart hand-written); unit-tested (`enrichCart` incl. JSON-key contract + empty→`[]`). **Guest path untouched.**
- **Closes:** **CT-01** (seller name + subtotal), **CT-04** (breakdown), **CT-05** (variant label) — live; **CHK-01/CHK-02 data-unblocked** (the review renders real lines + total; the full breakdown + per-seller grouping in the *review UI* is a fast-follow — data all present).
- **Still open (PR 2):** CT-02 free-shipping progress + CT-09 basket-discount (the shared discount cluster); CT-03/CHK-04 coupon (PR 3 if it balloons). Discovery: `docs/internal/cart-readpath.md`.

## 4j. Totals/discount display completion (`feat/cart-checkout-totals-completion`)

- **CHK-01 ✅ + CHK-02 ✅ shipped** — the **checkout review** now renders the full breakdown (subtotal/shipping/total + KDV note + cashback) and **groups by seller** (name + per-seller subtotal), on the #4i enriched cart. Pure display, reuses cart i18n keys (0/0), widget-tested.
- **CT-02 → NOT-ACTIONABLE** — cart shipping is **unconditionally 0** (cargo handled separately, §2.3/§4.8) → no threshold → a free-shipping *progress* bar has nothing to progress toward; not built.
- **CT-09 → DEFER (financial, not display)** — `basket_discount_pct` (#133) is a **display-only card pill not applied to any price/total**; surfacing a real "Sepette indirim" discount line requires applying it across pricing→order→payment→cashback (a money change, CLAUDE.md §4) → deferred to that pricing PR. (`ProductSummaryRow.BasketDiscountPct` is already resolved in `enrichCart`, ready for it.) Discovery: `docs/internal/cart-checkout-totals.md`.

## 4k. CT-09 basket-discount pricing — ✅ IMPLEMENT (seller-funded; `feat/basket-discount-pricing`)

- **Supersedes the earlier DEFER (commit `88df133f`).** Re-examination + owner confirmation: `basket_discount_pct` lives on `products` (a **seller-owned** attribute, like Trendyol's "Sepette indirim") → it is **definitionally seller-funded**, not an open CFO call. Under seller-funded the cashback **formula is unchanged** (`price` was always "the price the item sold for"; with the discount the item *sells for* the discounted price) → **no constitution bump**, no §12 trigger.
- **Discovery shift — the snapshot does the work.** Every fin-svc node derives from the `order_items` snapshot (cashback `priceMinor = Σ(unit_price×qty)`; orderledger `GrossMinor = total_minor`; payout reads `seller_net_minor`; returns refund `unit_price×qty`). So making `order_items.unit_price_minor` the **discounted** unit + freezing commission/KDV/net on the discounted gross means **every downstream consumer inherits the discount with zero code change**, and the capture ledger still balances exactly (`commission_revenue` residual = `total − Σnet − Σkdv` = `Σcommission`, D==C). **fin-svc untouched; no new accounts.**
- **Ships:** catalog `Variant.BasketDiscountPct` (via `GetVariantByID`); migration `0091_order_basket_discount` (`order_items.list_unit_price_minor`/`basket_discount_pct`, `orders.discount_minor`, all `DEFAULT 0`); `order/pricing.go` pure helper shared by `enrichCart` (display) **and** the order build (charge) → **display==charge guaranteed**; `Checkout` + `InitiateCheckout` saga apply the per-unit discount; cart/seller-breakdown "Sepette indirim" line; mobile DTO. Generic helper + single `orders.discount_minor` line so **coupon (CT-03/CHK-04) reuses it**.
- **Deliverable:** `docs/internal/basket-discount-pricing.md` (revised → seller-funded plan). The pill is now **honest** — the advertised basket discount is the charged one.

---

## 4l. Quick cross-surface functional gaps — ✅ RESOLVED (`feat/quick-functional-gaps`)

- **Three read-path-verified-cheap gaps from the surface audits, shipped together.** Discovery: `docs/internal/quick-gaps.md` (each confirmed cheap before building — the cart-stub lesson).
- **AC-02 — Help wired:** the account guest-menu Help row was `onTap: () {}` (dead); now `context.push('/help')` (the real `HelpIndexScreen` route). One-liner.
- **RT-04 — return status-history surfaced:** `return_status_history` rows (migration 0070) were written but never read. Added `ReturnRepository.ListReturnStatusHistory` + `ReturnService.GetReturnHistory` (ownership-scoped) → `GET /returns/{id}` gains a `history[]`; mobile renders the real event timeline (falls back to the status-derived one when empty). No refund-settlement change (RT-01 stays a separate financial lane).
- **OR-04 — reorder:** frontend-only; a "Tekrar sipariş ver" button on the order detail re-adds the order's items via the existing `cartProvider.addItem` (→ `POST /cart/items`), counting per-item OOS failures gracefully, then → `/cart`. No backend change.
- **Gates:** `flutter analyze` 0 (touched files), i18n `--strict` OK, order package tests green incl. new `GetReturnHistory` ownership tests. Audits AC-02/RT-04/OR-04 → RESOLVED.

## 4m. RT-01 — refund settlement (refund-as-coin) — ✅ RESOLVED (`feat/refund-settlement`)

- **The one genuinely-broken transaction flow: approved returns never refunded.** Discovery: `docs/internal/refund-settlement.md`. `SellerApprove` stopped at `approved` — nothing reached `refunded`, no coin/ledger/outbox → the refund card hung "pending" forever.
- **Trigger:** `SellerApprove` now settles atomically in one core-svc tx: pending→approved→**refunded** + both history rows + `ecom.return.refunded.v1` to `order_schema.outbox` (§4.5). Idempotent (pending-status guard + outbox key `return:refunded:<id>`).
- **Ledger treatment (refund-as-coin):** fin-svc `internal/refund` consumer mints the refund as Mopro Coin via `wallet.Service.Post` — **D `equity:refund_distribution:<COIN>` ↔ C the buyer wallet**, amount = `RefundAmountMinor` (the charged snapshot, CT-09+coupon-correct, partial-safe) credited 1:1. New equity account = **migration 0082** (+ chart seed), the analogue of `equity:cashback_distribution` → **§4-compliant, NOT a §12 change** (refund-as-coin is the audit-decided model, so no owner funding question). Idempotent on ledger key `refund:<return_id>` (wallet layer-3 returns the original txn id on replay). Emits `fin.refund.coin.credited.v1`.
- **Display:** `buildReturnRefundView.method = wallet_credit`; mobile already maps `RefundInfo.isWallet → returns.method_wallet` + `refunded → issued` (no mobile change).
- **Gates:** order + refund + wallet package tests green (settlement→refunded + event payload + history; consumer balanced-D/C + idempotency + zero-skip; producer→consumer wire-format contract); boundaries OK; `lint-discipline` 0; migration-safety OK; depguard `fin-no-ecom` now covers `internal/refund`. Audit RT-01 → RESOLVED.

---

## 4m. Orders absences bundle — OR-05/OR-07 ✅ RESOLVED, OR-02 🚩 DEFER (`feat/orders-absences`)

- **Read-path check before building (cart-stub lesson) → 2 of 3 were deeper than the audit's "cheap surfacing."** Discovery: `docs/internal/orders-absences.md`.
- **OR-05 — variant label — ✅ RESOLVED, but it was a STUB not a one-field add.** `GET /orders/{id}` served the **raw** `order_items` snapshot (only `variant_id`/`unit_price_minor`); the mobile `OrderItemDto` requires `title`+`price_minor` → detail items didn't render against the real backend. Built the §5 variant carrier `enrichOrderItems` (`GetVariantByID` + `ListProductsByIDs`, reuses `variantLabel`, no cross-schema JOIN, graceful per-item degradation) emitting title/variant_label/cover/price_minor — both adds the label and fixes the stub. `OrderItemDto.variantLabel` + hardened null parsing; line renders "Siyah, M". Contract + degradation tests.
- **OR-07 — per-order help — ✅ RESOLVED.** "Bu siparişle ilgili yardım" button → `/help` (like AC-02). i18n `order.help`.
- **OR-02 — delivery address — 🚩 DEFER (deeper than audited).** The order **never captures** an address (no schema column, no domain field, `InitiateCheckoutRequest` has none; mobile selects an `Address` only to derive the PSP buyer name). Nothing to surface → a checkout-capture vertical (snapshot in the initiate body + orders schema + handler + mobile send), out of the variant-carrier scope. Precise plan in the discovery doc.
- **Gates:** core-svc build + tests green (incl. `enrichOrderItems` contract/degradation); `flutter analyze` 0 (touched); i18n `--strict` OK; §5/boundary clean (catalog Service carrier). Audit OR-05/OR-07 → RESOLVED, OR-02 → DEFER.

## 4n. Returns UI polish — RT-06 ✅ RESOLVED, RT-05 🚩 DEFER (`feat/returns-ui-polish`)

- **No-codegen lane, parallel-safe with OR-02.** Read-path check before building decided ship-vs-defer for each. Discovery: `docs/internal/returns-ui.md`.
- **RT-06 — consumer status filter — ✅ RESOLVED (pure client).** A horizontal status chip bar on the return-history list (İadelerim). The list is already fetched and each `ReturnListItemDto` carries `status`, so a `returnsStatusFilterProvider` (`StateProvider<String?>`) + an in-memory `.where(status)` is all it takes — **no backend, no extra fetch, no codegen.** The bar offers "All" + one chip per status *present* in the list (so every filter has matches); if a refresh drops the last return of the selected status it falls back to "All"; hidden entirely for a single-status list (keeps the populated golden pixel-stable). i18n `returns.filter_all` (all 4 locales).
- **RT-05 — per-item reasons — 🚩 DEFER (read-path confirmed, needs a response field).** The detail response does **not** carry per-item reasons: `order_schema.return_items` (migration 0070) and the `ReturnItem` struct hold only `order_item_id`+`quantity`; the reason lives on the return header. Surfacing per-line reasons needs a migration + `CreateReturn`/`GetReturn` change + an OpenAPI/codegen change (`reasons[] per line`) → out of the no-codegen lane (kept conflict-free with OR-02's codegen lane), re-scoped with the heavier returns items (RT-02 cargo-leg, RT-03 photos).
- **Gates:** returns list screen tests green (4 new: bar hidden single-status / shown mixed / chip filters / All restores); `flutter analyze` 0 new (touched screen clean; pre-existing order-package infos untouched); i18n `--strict` 0 extra + usage ratchet 0 dead/0 missing; no Go, spec, or codegen change. Goldens: local macOS run fails all order goldens (incl. untouched timeline/refund cards) = known font skew, not a flip — single-status layout unchanged, not rebaselined (informational, non-required job). Audit RT-06 → RESOLVED, RT-05 → DEFER.

---

## 5. CI / branch-protection

- **F-022b (#138)** made `flutter analyze` green-on-compile (`--no-fatal-infos`; errors/warnings still fatal).
- **Branch-protection PATCH — ✅ APPLIED 2026-06-10 (`chore/gate-finalize`, #164/#165).** `main` now **requires 14 substantive contexts**: `verify`, `flutter analyze`, `flutter test` (logic only — see goldens below), `build_runner (verify generated files up-to-date)`, `i18n completeness (extras gate)`, `i18n dead-key gate`, `riverpod inference gate`, `dart analyze (mopro_api generated client)`, `govulncheck ./...`, `Go build + contract tests`, `Generated files in sync`, `Spectral OpenAPI lint`, `Flutter analyze (dart-dio client)`, `refuse-pr-from-default-branch`. `strict=false`; **`enforce_admins=false`** (an admin escape hatch — no lockout if CI flakes; flip to `true` for a truly un-bypassable gate); no PR-review requirement (green PRs self-merge → zero manual). To make these requirable **without blocking unrelated PRs**, the gate workflows (flutter-ci, openapi-ci, govulncheck) had their PR `paths:` filters removed so every gate posts on every PR. Validated: #165 (a real PR) self-merged through all 14 green.
- **Goldens → INFORMATIONAL (kills the PAT requirement) — ✅ (`chore/gate-finalize`).** The 23 `*_goldens_test.dart` are tagged `@Tags(['golden'])` (+ `mobile/dart_test.yaml`); the required `flutter test` runs `--exclude-tags golden` (logic) and a **non-required** `flutter golden (informational)` job runs `--tags golden`. A golden flip can never block a merge → the rebaseline bot needs **no PAT**: `golden-rebaseline.yml` reverted to `GITHUB_TOKEN`. **`GOLDEN_REBASELINE_PAT` is no longer required by anything** (optional nice-to-have only). Discovery shift: a direct-to-`main` rebaseline push is rejected by branch protection (`GH006`), so the bot pushes to a branch → PR → merge (did this for the PD-07 reviews-tab goldens, greening `main`).
- **Vuln scanner consolidated — ✅ (`chore/ci-cleanup`):** `govulncheck.yml` and `security-scan.yml` ran the identical `govulncheck ./...` scan. Merged to one canonical scanner: `govulncheck.yml` now triggers on **push:[main] + path-filtered PR + weekly + dispatch** (fail-on-vuln exit-3 unchanged); `security-scan.yml` deleted. Required context `govulncheck ./...` unchanged.
- **Stale PLP-14 toggle goldens — ✅ re-baselined (`chore/ci-cleanup`):** the `golden-rebaseline` workflow regenerated the 9 `*_sidebar_*` baselines (#153 added the price-drop toggle row but left them un-rebaselined). Only `*_sidebar_*` flipped. (Also unblocked a main red: 2 search-UI test fakes missing the `priceDropped` param — `search_ports_test`/`search_recovery_test` — threaded through.)
- **Codegen-drift gate — ✅ closed (`fix/mopro-api-gen-sync`):** the `build_runner (verify generated files up-to-date)` job ran build_runner only with `working-directory: mobile` (the app) → the **`mopro_api` path-dependency package's `.g.dart` was never regenerated/checked** and drifted. Live impact: `product_summary.g.dart` dropped `isBestseller`/`basketDiscountPct` deserialization, so the shipped "Çok Satan" stamp + "Sepette %X" pill **silently didn't render on the real API path** (widget tests bypass `fromJson`). Regenerated 2 stale files (product_summary + delivery_eta), added a package `build_runner` + `git diff --exit-code` step to the same job, and a `ProductSummary.fromJson` regression test. Required context name unchanged. Protects the upcoming PLP-13/17 codegen verticals. See `docs/internal/gen-sync.md`.
- **CI-hygiene-2 — golden version skew + worktree lint + rebaselines (`chore/ci-hygiene-2`):** Three accumulated CI-hygiene fixes (`docs/internal/ci-hygiene-2.md`). **(1) Golden version skew ✅** — every `subosito/flutter-action` step floated on `flutter-version: '3.x'` (there was **no `stable-3.44.1` pin** — the premise was inverted), so goldens baselined on an older 3.x were compared by the `golden` job on a newer 3.x → the informational `flutter golden` job was perpetually red from **toolchain drift, not real regressions**. Pinned an exact `FLUTTER_VERSION=3.44.1` (workflow-level env in `flutter-ci.yml`; same literal + keep-in-sync comment in `golden-rebaseline.yml`/`make-verify.yml`/`openapi-ci.yml`). golden + rebaseline now share the toolchain. **(2) Pre-push `--no-verify` retired ✅** — `make lint`'s golangci-lint `lax` generated-file exclusion silently broke from a git worktree (it reported this module's files under an out-of-tree `../<other-worktree>/internal/api/gen/…` prefix — stale golangci build cache, sometimes a deleted worktree — so the `DO NOT EDIT` header match failed and `server.gen.go` {core,fin} false-positived). Added `linters.exclusions.paths: [internal/api/gen]` (unanchored substring → worktree-robust) + explicit `generated: lax`; `golangci-lint run` now exits 0 from a worktree → **no more `git push --no-verify`** (CI was never affected: clean checkout + fresh cache). **(3) Rebaselines** — regenerated on the pinned 3.44.1 via the `golden-rebaseline` workflow on the branch (CT-09 filled-cart + CT-03 coupon line + skew baselines); the informational golden job goes green. The earlier `--no-verify` habit (e.g. PR #182) is retired.
- **Stabilize main — `nightly-soak` startup_failure (`chore/stabilize-main`):** After #182–#185 merged, main was "merged but not green." Diagnosis (`docs/internal/stabilize-main.md`): all **13 check-runs green** on HEAD (incl. the informational `flutter golden` — #184's UI edits didn't move any covered golden, so no rebaseline was needed; and #185 already fixed the coupon-DDL `verify` red). The lone red was the **`nightly-soak` workflow's startup_failure** — a check-**suite** failure (0 jobs, `event=push`) GitHub raises on every push because the workflow file is invalid; it's neither a required context nor a PR check (schedule/dispatch-only) but it stamps every commit with a ❌. **Long-standing, not from the batch:** it has startup-failed on every push since `nightly.yml` was added (2026-06-03). **Root cause:** the `gh issue create --body "…"` multi-line string put its `Run: ${{…}}` line at column 0, below the `run: |` block-scalar indent → YAML ended the scalar and parsed `Run:` as a top-level workflow key (`unexpected key "Run"`, per actionlint) → startup_failure. (Plain `yaml.safe_load` accepts it, which is why it slipped.) **Fix:** collapse `--body` to a single line; actionlint clean + a syntax sweep of all workflows finds no other startup-failure-class issues. **Lesson restated:** #182 merged with a red `verify` via `enforce_admins=false`, which is what let the e2e-DDL regression (#185) reach main — the admin override is for confirmed flakes only, and new goldens get rebaselined in the PR that flips them.
- **Gen-drift + pre-push root fix — ✅ (`chore/gen-drift-prepush`).** #190 merged with **"Generated files in sync" red**, and the recurring `--no-verify` was the deeper cause. `docs/internal/gen-drift-prepush.md`. **(1) Drift fixed (no override) ✅** — the Go gen was already in sync; the red was a single **non-deterministic** line in the dart `FILES` manifest (`test/delivery_address_test.dart`, re-added by #190 after `1c6ca076` had stripped such test-stub lines). Regen drops it; a second regen confirms it stays gone. **(2) `Order` status enum reconciled ✅** — the spec enum was fictional (`pending, confirmed, preparing, …`) vs the backend truth (`internal/order.OrderStatus`: `pending_payment, paid, shipped, delivered, cancelled, refunded, partially_refunded`); reconciled both the `Order` schema and the `GET /orders?status=` filter param (+ the stale "pending/confirmed" cancel-summary wording), regenerated Go+Dart. The gen `OrderStatus` constants are unreferenced outside `internal/api/gen` → build-safe (oapi-codegen collision-name re-disambiguation is expected). Contract test now asserts `status="paid"` ∈ the `Order.status` enum. **Discovery shift:** the enum was NOT the only `Order` divergence — the envelope emits `items` as a *sibling* of `order` while the schema *nests* it, so a full-`Order` assertion still fails on missing nested `items`; that's a separate response-shape change (touches the mobile read-path), DEFER'd as a follow-up. **(3) Pre-push retired `--no-verify` for real ✅** — the hook ran the full `make verify`, whose `property-*`/`integration-*` suites need the PG+Redis test clusters; without them the cashback DB crons hang → reflexive `--no-verify` → the local gate stopped running. New **`make verify-fast`** (the hook now calls it) runs only the DB/Docker-free steps — `fmt vet lint-discipline boundaries migration-check build-all test analyze i18n-check i18n-usage` (+ new `analyze` = `flutter analyze --no-fatal-infos`, mirrors CI) — **end-to-end ~35s, exit 0, no hang**. The full `verify` (property + integration) stays the **CI required gate, unchanged**; golangci `lint` deliberately stays in CI (the worktree gen-file false-positive foot-gun from `ci-hygiene-2`). This is the local-gate restoration the previous bullet's lesson asked for.

---

## 6. DEFER pile (lower priority, no clock)

| Item | Note |
|---|---|
| riverpod 2.x → 3.x migration | Deliberate task; Dependabot now ignores majors. |
| very_good_analysis ~199 analyze infos | Clear over time, then drop `--no-fatal-infos`. |
| mood-strip golden | Needs a network-image mock harness (CachedNetworkImage fires real HttpClient). |
| Footer `about` / `terms` pages | HP-09 DEFER — currently routed to `/help`. |
| Dead legacy columns | `discount_price_minor`, `rating_stars` — API no longer reads them. |
| init vs migration 0078 (`sellers`) | Provisioning-snapshot drift; prod already provisioned. |
| `local-phaseb.sh` orchestrator | Dev tooling, never merged to main. |
| PLP-16 bestseller rank (backend-surface) | Rank exists in `analytics_schema.popular_products`; surface as `ProductSummary.bestseller_rank` (handler app-merge, §5-safe) + spec/codegen + ranked card badge ("Çok Satan N"). Own task. |
| PLP-09 fast-delivery flag (backend) | No `fast_delivery`/delivery-SLA column or API param — add the flag first, then a badge/filter. |
| ~~PLP-17 official-seller flag (backend)~~ | **✅ RESOLVED** (`feat/plp-17-official-seller`, §4f) — `is_official` + §5-safe carriers + badge on PLP card & PDP seller card. |

---

## 7. Phase B surface progress

| Surface | Status |
|---|---|
| Home | ✅ Parity-complete (IA-01/02, Sprints A/B, closeout #135–#137) within the Deliberately-Lean IA. |
| PLP / category browse | **UI parity ~done** — canonical registry `docs/audits/TRENDYOL_PARITY_PLP_AUDIT.md`. **RESOLVED:** PLP-01/03 (#142), PLP-04/05 (count+breadcrumb), **PLP-15/18/19/20** (numbered pages / sticky sidebar [already-matched] / ultra-wide breakpoints / sticky mobile bar, `feat/plp-layout-closeout`). **DEFER'd (backend):** **PLP-13** attribute facets (§4b), **PLP-12** rollup (§4). **Open CONFIRMED:** PLP-14 price-history (backend), PLP-09 fast-delivery. Remaining = MED/LOW polish + PROBABLE visual items awaiting Salih's live walk (§9). **ID re-map:** contract `PLP-02/05/07` (sticky sidebar / ultra-wide grid / sticky mobile bar) = **PLP-18/19/20**. |
| Search | Pending (inherits PLP grid/filter patterns). |
| PDP | Pending (own walk; may need seed extension: reviews/variants/gallery). |
| Phase C (divergences) | After parity surfaces — coin redeem (deferred), etc. |

### Local walk env refreshed — ✅ (`chore/local-walk-env`)

The full walk env was last set up many PRs/migrations ago. Refreshed on current `main`: rebuilt all 3 service images, brought both DBs **to head** (the local stack seeds schema from `init/*.sql` with **no `schema_migrations`/auto-migrate**, so it had drifted — ecom was a patchwork at ~0082/0089 missing 0083/0087/0090–0093; ledger missing 0082), ran all seeds, and seeded a **logged-in test user** (`walk@mopro.local`) with cart (multi-seller) / favorites / 2 addresses / **6 orders across 5 statuses** / **3 returns across 3 statuses** / coin. Reusable, idempotent: `scripts/dev/local-walk-seed.sh` (reconstructs the never-merged `local-phaseb.sh`) + `WALK_READINESS.md` (per-surface yes/partial + creds). **Two real main bugs found + fixed** bringing it up: `jobs-svc` had no `time/tzdata` embed → crash-looped on `Europe/Istanbul` on distroless (would fail in prod too); migration `0091` carried a stray `</content>` authoring tag that breaks `migrate-tool up`. Discovery shifts: login **does** enforce `email_verified` (seed flips it in-DB); coin balance is materialized (the only "partial" — seed posts a balanced ledger entry, full balance flows from the cashback cron); all 10 surfaces confirmed rendering against the rebuilt backend. Doc: `docs/internal/local-walk-env.md`. **Unblocks Salih's ten-surface walk.**

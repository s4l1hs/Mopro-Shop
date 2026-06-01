# Audit — `seller.slug` on Product DTO (PDP→storefront unblock)

Confirms the gap shape before code. Each row: file:line + observation.

## Branch-point divergence from the prompt (§1)

- **Tranche 5a is NOT merged to `main`.** `main` is at `3234ac92` (legal-copy
  merge, pre-5a). The 5a commits (`5ba19d53`..`6b2b2eff`) — incl. the
  `/sellers/:slug` route, `SellerStorefrontScreen`, and the `PdpSellerCard`
  no-op `onTap` this PR wires — live on `feat/seller-facing-and-platform-growth`.
- **Decision:** branch `chore/seller-slug-in-product-dto` off the current 5a
  branch (stacking), NOT main — otherwise the route this PR targets wouldn't
  exist. `make verify` is green on the branch-point (no §1.1 hygiene commit).

## 2.1 Current Product DTO shape

- `api/openapi.yaml:2223` `Product` schema (full detail). `required:` includes
  `seller_id`, **`seller_name`**, but NOT a slug. Fields are **`snake_case`**
  (`seller_id`, `seller_name`) → the new field is **`seller_slug`**.
- `api/openapi.yaml:2264` `ProductSummary` (list/search) — separate schema, has
  `seller_id` but no `seller_name`/slug. **Not consumed by `PdpSellerCard`.**
- Generated Dart DTO: `mobile/packages/mopro_api/lib/src/model/product.dart` —
  `sellerId` + `sellerName` (both `required`). `checked: true`,
  `disallowUnrecognizedKeys: false` (tolerates unknown keys).
- Generated Go types: `internal/api/gen/types/types.gen.go` (oapi-codegen).

**Placement decision:** add `seller_slug` to `Product` only (the PDP DTO).
`ProductSummary` is excluded — list/search/storefront cards don't deep-link to a
storefront, and adding it there would force `seller_slug` into many list handlers
(category, search, home rails, storefront-by-seller), blowing the minimal-diff
non-goal (§0). If list-card seller links are ever wanted, that's a separate PR.

**Nullability:** `seller_slug` is **nullable**. Pre-5a products carry arbitrary
`seller_id`s (test data 100/77/…) with no matching `seller_schema.sellers` row,
and a seller may be `suspended` (hidden by `seller.Service`). Unresolved → null.
`PdpSellerCard` already hides its link when `onTap == null`, mapping 1:1 to a null
slug, so no non-functional CTA renders.

## 2.2 Backend response shape

- `cmd/core-svc/catalog_handlers.go:124` `handleGetProductDetail` returns
  `"product": p` where `p` is `catalog.Product`.
- `internal/catalog/domain.go:44` `catalog.Product` has `SellerID` but **no
  `SellerName` and no `SellerSlug`** → the live response emits **neither**
  `seller_name` nor a slug, despite the spec marking `seller_name` required.
  (`internal/api/contract_test.go:85` validates a hand-built fixture that *adds*
  `seller_name`, so the schema is satisfiable, but the handler doesn't populate
  it — a latent spec/handler drift.)
- **Fix:** wire `seller.Service` (Tranche 5a, `GetByID(sellerID) → {Slug,
  DisplayName}`) into `handleGetProductDetail`; emit both `seller_slug` (null on
  `ErrSellerNotFound`) and `seller_name` (`""` on unresolved) via a thin response
  struct embedding `catalog.Product`. Cross-module orchestration in a cmd handler
  is the established pattern (`handleReviewEligibility`, the storefront handlers).
  This is in-scope per §0 ("changes what the product detail endpoint includes").

## 2.3 PdpSellerCard current state

- `mobile/lib/features/catalog/widgets/pdp/pdp_seller_card.dart:10` — takes
  `sellerName` + optional `onTap`; renders the "Mağazaya git" `TextButton` only
  `if (onTap != null)`. Presenter-agnostic (shared mobile/desktop renderer).
- **One** call site: `mobile/lib/features/catalog/screens/product_detail_screen.dart:444`
  — `PdpSellerCard(sellerName: product.sellerName, onTap: () {})` (no-op). This
  is the carry flagged in the Tranche 5a REPORT.
- **Wiring plan:** keep the card presentation-agnostic; pass a real `onTap` from
  the screen that does `context.push('/sellers/${product.sellerSlug}')` when the
  slug is non-null, else pass `null` (card hides the link). Add a11y (semantic
  label "Satıcı mağazasını görüntüle", keyboard activation) on the card's button.

## 2.4 OpenAPI regen mechanism

- `Makefile:292-314` — `api-gen-models|core|fin` via `oapi-codegen` (`go run`,
  emits `internal/api/gen/…`); `api-gen-dart` via **Docker**
  `openapitools/openapi-generator-cli:v7.10.0` → `mobile/packages/mopro_api`.
  `make api-gen` runs all four.
- Docker image `openapitools/openapi-generator-cli:v7.10.0` is **present
  locally** → `api-gen-dart` runs offline, no pull.
- `Makefile:321` `api-check-sync` diffs `internal/api/gen/` **and**
  `mobile/packages/mopro_api/` → both must be regenerated + committed.
- Dart generator config: `dart-dio` + `json_serializable`,
  `disallowUnrecognizedKeys:false`; no custom name overrides → `seller_slug` maps
  to `sellerSlug` automatically.

## 2.5 Output

No reality blocks the plan. One adaptation surfaced: §3 must add a small handler
change (resolve seller → emit `seller_slug` + the currently-missing `seller_name`)
so the new field is actually populated — without it the link would never appear.

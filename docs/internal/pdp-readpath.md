# PDP read-path fix + contract conformance — PD-06 / PD-07 (discovery)

> Fixes the server↔spec drift behind the blocked PDP walk and adds the systemic
> guard so the drift class (F-021 → GEN-SYNC → PD-06) stops recurring. Lane owns
> the catalog server read paths, the spec, codegen, and the contract test.

## PD-06 — the gap is bigger than "emit image_urls" (no codegen)

**Discovery shift.** `GET /products/{id}` (`handleGetProductDetail`,
`cmd/core-svc/catalog_handlers.go`) returns a **legacy envelope**:
```
{ product: {…}, variants: [{… image_keys, cover_image_url}], translations: [...],
  cashback_preview, delivery_eta }
```
But the OpenAPI 200 schema is the **flat `Product`** (`required: [id, seller_id,
seller_name, category_id, brand, status, title, description, variants,
cashback_preview, created_at]`) with `variants[]` = **`Variant`** (`required:
[…, image_urls]`, **no `image_keys`**). The **mobile generated client agrees with
the spec**: `getProduct → Response<Product>` (flat; `id/seller_name/variants[]`
top-level) and `Variant.imageUrls` (`image_urls`, `required: true`).

So **the server is the sole outlier** — spec + client are already flat-with-
`image_urls`. Live-verified: `/products/15` top-level keys are
`[cashback_preview, delivery_eta, product, translations, variants]` (no top-level
`id`); variant carries `image_keys` (full URLs) + `cover_image_url`, **no
`image_urls`**. The strict generated parse fails on the real backend (the PDP
never worked end-to-end) — which is why the walk is blocked.

**Fix (no codegen — spec + client unchanged):** rewrite the handler to emit the
flat, spec-conformant `Product`:
- Promote `id/seller_id/seller_name/seller_slug/category_id/brand/status/created_at`
  to the top level (was nested under `product`).
- **`title`/`description`** — resolve from `translations` by the request locale
  (`parseLocale`, fallback to `defaultLocale` then first); add a `defaultLocale`
  param to the handler (wire from `main.go`). Drop the `translations` array (the
  spec has no such field; **mobile doesn't consume it** — only `main.dart` /
  `consent_copy.dart` "translations" are unrelated easy_localization).
- **Variant** → emit spec fields incl. **`image_urls`** = `image_keys` mapped
  through **`mediaurl.CDNUrl`** (the same helper already used for
  `cover_image_url` + `ProductSummary.cover_image_url`); drop `image_keys` /
  `cover_image_url` / `product_id` / `category_id` / `seller_id` (not in the spec
  `Variant`). Keep `original_price_minor` / `lowest_30d_price_minor` (already
  selected per-variant).
- Update `product_detail_handler_test.go` (asserts fields under `"product"` →
  move to top level).

## PD-07 — reviewer name + photos (codegen)

- `ListReviews` (`repository.go`) / `reviewJSON` (`home_handlers.go`) return
  `id/userId/rating/title/body/helpfulCount/votedByCurrentUser/createdAt` — **no
  reviewer name, no photos**. The reviews 200 schema needs the new fields → codegen.
- **Reviewer name (§5-safe):** `product_reviews.user_id` is a soft ref to
  `identity_schema.users` — resolve via **`identity.Service`** in-process (NOT a
  cross-schema JOIN). Mask Trendyol-style ("A** Y**").
- **Photos (§5-safe):** `attachments_schema.photo_attachments` (`entity_type='review'`,
  soft-ref `entity_id`) — resolve via **`attachments.Service`** in-process (NOT a
  JOIN across `attachments_schema` ↔ `catalog_schema`). CDN-map the storage keys.
- (Per §5 split-bailout: if the attachments fan-out is heavy, ship reviewer-name
  first + DEFER photos.)

## Contract hardening — the systemic catch

**Why PD-06 slipped:** `internal/api/contract_test.go` is **fixture-only** — it
validates hand-crafted fixtures against the spec (and the F-021 GetProduct fixture
*has* `image_urls`); it **never calls a live handler** (explicit comment: "These
tests do NOT call live handlers"). So a handler that omits a required field is
invisible to it.

**Fix:** a **live-handler conformance** test — call the real handler with stub
services, capture the JSON, and `VisitJSON` it against the endpoint's OpenAPI
schema. Handlers live in `package main` (`cmd/core-svc`), so the test lives there.
Extend `make contract-test` + `.github/workflows/openapi-ci.yml` to run
`-tags=contract ./cmd/core-svc/...` too. Covers `/products/{id}` now (would have
failed on the envelope/`image_keys`) and the reviews endpoint in PR 2.

## Sequencing (per §5)

- **PR 1 — PD-06 + detail conformance test** (no codegen): flatten GetProduct →
  spec `Product` with `image_urls`; add the live-handler contract test for
  `/products/{id}` (fails on the old envelope, passes after) + wire it into
  contract-test/CI. Unblocks the whole PDP.
- **PR 2 — PD-07 + reviews conformance** (codegen): reviewer name + photos; extend
  the contract test to the reviews endpoint.

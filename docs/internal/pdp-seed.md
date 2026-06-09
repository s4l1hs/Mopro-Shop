# PDP walk enabler — seed gallery + variants + reviews (discovery)

> The PDP walk is blocked on **data**: the base seed is 1 product : 1 variant : 1
> image, **0 multi-variant products, 0 reviews** (verified live: 50 products / 50
> variants / 0 `product_reviews`). This seeds one product rich enough to exercise
> the gallery, variant selector (incl. OOS), and reviews. Dev-only, idempotent,
> §5-safe. Mirrors `merch-extras.sql` / `plp-density-extras.sql`.

## How the extras seed works (the pattern to mirror)

Hand-written, idempotent, **LOCAL-ONLY** SQL — never fabricates products, only
re-points/adjusts existing SKUs, keyed on the stable `variants.sku`. Applied
after `make seed`:
```
docker exec -i postgres-ecom psql -v ON_ERROR_STOP=1 \
  -U ecom_admin -d mopro_ecom < scripts/seed/data/pdp-walk-extras.sql
```
(Not wired into `make seed` — `scripts/dev/local-phaseb.sh` is not on `main`. The
seed binary `scripts/seed/cmd/seed` loads the JSON; the `*-extras.sql` files are a
separate manual psql apply.)

## Schema (catalog_schema, single-schema — §5-safe)

- **Gallery** → `variants.image_keys TEXT[]`. The base seed puts **1** key per
  variant; the keys are already **full URLs** (live check: `https://placehold.co/...`),
  so they render directly. Upsert key: `variants_sku_uq (sku)`.
- **Variants** → `variants(product_id, sku, color, size, price_minor,
  price_currency DEFAULT 'TRY', stock, image_keys, original_price_minor)`. The PDP
  variant selector groups by **`color` × `size`**; **OOS = `stock = 0`** (P-015).
  `original_price_minor > price_minor` ⇒ buy-box strikethrough (PDP-strikethrough).
  A price UPDATE fires the 0083 history trigger → also feeds `lowest_30d`.
- **Reviews** → `catalog_schema.product_reviews(product_id, user_id, rating 1..5,
  title, body, helpful_count, status DEFAULT 'published', submitted_locale)`,
  `UNIQUE(product_id, user_id)` (upsert key), **no FK on `user_id`** (soft ref →
  synthetic ids fine). `helpful_count` is a denormalized cache (authoritative
  source `review_helpful_votes`); setting it directly is enough for display.

## How the PDP reads them (live-verified against core-svc)

- **Reviews — WORKS.** `GET /products/{id}/reviews` → `ListReviews` (list +
  `helpful_count`) + `ReviewsSummary` (histogram via `GROUP BY rating`, keys 1..5
  + average). Empty now → seeding varied ratings populates the histogram + average.
- **Variants — WORKS.** `GET /products/{id}` returns the `variants` array with
  `color/size/stock` — the selector + OOS state read straight from these.

## ⚠️ Discovery shifts (read-path gaps the walk must note)

1. **Gallery is blocked by a server contract drift, NOT seed data (PD-06).** The
   `GET /products/{id}` handler emits each variant's **`image_keys`** (array) +
   **`cover_image_url`** (image_keys[0]) but **NOT** the spec-required
   `Variant.image_urls` (OpenAPI `Variant.required: [...image_urls]`). The mobile
   gallery reads `selectedVariant.imageUrls` (generated model, `image_urls`
   `required: true`). **Live response confirms `image_urls` is absent.** So the
   multi-image gallery will not render — and `getProduct` likely fails the strict
   generated parse — until the **server emits `image_urls`** (map `image_keys`
   → CDN). That is a PDP/server fix (out of scope here; not codegen either —
   regenerating the client won't add a field the server never sends). **We still
   seed the `image_keys` gallery so the data is walk-ready the moment PD-06 lands.**
2. **Review photos are not surfaced (PD-07).** Schema supports them
   (`attachments_schema.photo_attachments`, `entity_type='review'`, soft-ref
   `entity_id`), but `ListReviews` / `reviewJSON` return **no photos** (and no
   reviewer name). Seeding `photo_attachments` would not render → **not seeded**;
   surfacing them is a post-walk read-path fix.
3. **No real phone in the seed.** The catalog is the `plp-density-extras` fixture
   (≈28 brand-incoherent SKUs re-pointed into `elektr-kea`). Target an **apparel**
   product — `MP-S001` (Nike Dri-FIT, product 15) — where **color × size** is the
   natural Trendyol variant model (vs phone color × storage).

## Target & plan

`MP-S001` (product 15): 5 variants (Siyah S/M/L + Beyaz M + Lacivert M, **Siyah/L
`stock=0` OOS**), a 4–6 image gallery per variant, a strikethrough on the primary,
and 7 reviews (ratings 5/5/5/4/4/3/2 → avg ≈ 4.0) with varied helpful counts +
`products.rating_avg/rating_count` updated to match. All idempotent upserts.

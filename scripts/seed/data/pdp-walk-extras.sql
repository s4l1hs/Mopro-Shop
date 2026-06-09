-- scripts/seed/data/pdp-walk-extras.sql — dev-only PDP-walk enabler (PDP-SEED).
--
-- The base seed is 1 product : 1 variant : 1 image with 0 reviews, so the PDP's
-- gallery, variant selector, and reviews never render. This enriches ONE product
-- — MP-S001 (Nike Dri-FIT Essential, apparel: color × size is the natural variant
-- model) — into a walk fixture:
--   • Gallery   — 4–6 image_keys per variant (full placehold.co URLs, renderable).
--   • Variants  — 5 (Siyah S/M/L + Beyaz M + Lacivert M), incl. an OUT-OF-STOCK
--                 one (Siyah/L, stock=0 → exercises P-015), + a strikethrough.
--   • Reviews   — 7 with varied ratings (5/5/5/4/4/3/2 → avg ≈ 4.0), varied
--                 helpful counts + bodies → populates the histogram + helpful UI.
--
-- Real-shaped — enriches an EXISTING product (never fabricates a new one).
-- Idempotent (ON CONFLICT upserts keyed on the stable variants.sku /
-- product_reviews UNIQUE(product_id,user_id); re-runnable). LOCAL ONLY —
-- postgres-ecom. `make seed` resets the base rows; re-apply this after it.
-- Mirrors merch-extras.sql / plp-density-extras.sql.
--
-- ⚠ Gallery render is gated on PD-06 (server must emit Variant.image_urls; it
--   currently sends image_keys + cover_image_url). This seed makes the image_keys
--   data walk-ready; the gallery shows them once that read-path fix lands.
--
-- Apply (after `make seed` populates the catalog):
--   docker exec -i postgres-ecom psql -v ON_ERROR_STOP=1 \
--     -U ecom_admin -d mopro_ecom < scripts/seed/data/pdp-walk-extras.sql
-- Then walk the MP-S001 PDP (/products/<its id>).

BEGIN;

-- Resolve the target product id from the stable base-seed SKU (MP-S001). All
-- writes below key off this — no hardcoded product id.
DO $$
DECLARE
  pid BIGINT;
BEGIN
  SELECT p.id INTO pid
    FROM catalog_schema.products p
    JOIN catalog_schema.variants v ON v.product_id = p.id
   WHERE v.sku = 'MP-S001';
  IF pid IS NULL THEN
    RAISE EXCEPTION 'pdp-walk-extras: base SKU MP-S001 not found — run `make seed` first';
  END IF;

  -- ── 1) Variants: color × size, one OUT-OF-STOCK (Siyah/L). ────────────────
  -- The existing MP-S001 row becomes Siyah/M; four siblings are added. Galleries
  -- are colour-themed full URLs (render directly; the base seed uses the same
  -- placehold.co host). original_price_minor > price_minor ⇒ buy-box strikethrough.
  INSERT INTO catalog_schema.variants
    (product_id, sku, color, size, price_minor, price_currency, stock, image_keys, original_price_minor)
  VALUES
    (pid, 'MP-S001',       'Siyah',    'M', 129900, 'TRY', 42, ARRAY[
        'https://placehold.co/600x750/111111/FFFFFF/png?text=Nike+Siyah+1',
        'https://placehold.co/600x750/222222/FFFFFF/png?text=Nike+Siyah+2',
        'https://placehold.co/600x750/333333/FFFFFF/png?text=Nike+Siyah+3',
        'https://placehold.co/600x750/444444/FFFFFF/png?text=Nike+Siyah+4',
        'https://placehold.co/600x750/555555/FFFFFF/png?text=Nike+Siyah+5'], 159900),
    (pid, 'MP-S001-SY-S',  'Siyah',    'S', 129900, 'TRY', 30, ARRAY[
        'https://placehold.co/600x750/111111/FFFFFF/png?text=Nike+Siyah+1',
        'https://placehold.co/600x750/222222/FFFFFF/png?text=Nike+Siyah+2',
        'https://placehold.co/600x750/333333/FFFFFF/png?text=Nike+Siyah+3',
        'https://placehold.co/600x750/444444/FFFFFF/png?text=Nike+Siyah+4'], 159900),
    (pid, 'MP-S001-SY-L',  'Siyah',    'L', 129900, 'TRY',  0, ARRAY[
        'https://placehold.co/600x750/111111/FFFFFF/png?text=Nike+Siyah+1',
        'https://placehold.co/600x750/222222/FFFFFF/png?text=Nike+Siyah+2',
        'https://placehold.co/600x750/333333/FFFFFF/png?text=Nike+Siyah+3'], 159900),
    (pid, 'MP-S001-BZ-M',  'Beyaz',    'M', 129900, 'TRY', 22, ARRAY[
        'https://placehold.co/600x750/dddddd/333333/png?text=Nike+Beyaz+1',
        'https://placehold.co/600x750/eeeeee/333333/png?text=Nike+Beyaz+2',
        'https://placehold.co/600x750/cccccc/333333/png?text=Nike+Beyaz+3',
        'https://placehold.co/600x750/bbbbbb/333333/png?text=Nike+Beyaz+4'], NULL),
    (pid, 'MP-S001-LC-M',  'Lacivert', 'M', 134900, 'TRY', 14, ARRAY[
        'https://placehold.co/600x750/1f3a8c/FFFFFF/png?text=Nike+Lacivert+1',
        'https://placehold.co/600x750/24449c/FFFFFF/png?text=Nike+Lacivert+2',
        'https://placehold.co/600x750/2a4fad/FFFFFF/png?text=Nike+Lacivert+3',
        'https://placehold.co/600x750/305abd/FFFFFF/png?text=Nike+Lacivert+4'], NULL)
  ON CONFLICT (sku) DO UPDATE SET
    color                = EXCLUDED.color,
    size                 = EXCLUDED.size,
    price_minor          = EXCLUDED.price_minor,
    price_currency       = EXCLUDED.price_currency,
    stock                = EXCLUDED.stock,
    image_keys           = EXCLUDED.image_keys,
    original_price_minor = EXCLUDED.original_price_minor;

  -- ── 2) Reviews: varied ratings → histogram + average; varied helpful. ─────
  -- Synthetic user_ids (90090xx) — product_reviews.user_id is a soft ref (no FK).
  INSERT INTO catalog_schema.product_reviews
    (product_id, user_id, rating, title, body, helpful_count, status, submitted_locale, created_at)
  VALUES
    (pid, 9009001, 5, 'Bayıldım',          'Kumaşı çok kaliteli, terletmiyor. Beden tam oturdu.',            37, 'published', 'tr', now() - INTERVAL '21 days'),
    (pid, 9009002, 5, 'Spor için ideal',    'Koşuda hiç rahatsız etmedi, nem kontrolü gerçekten iyi.',        24, 'published', 'tr', now() - INTERVAL '18 days'),
    (pid, 9009003, 5, 'Tekrar alırım',      'İkinci kez sipariş ettim, rengi solmuyor.',                      12, 'published', 'tr', now() - INTERVAL '14 days'),
    (pid, 9009004, 4, 'Güzel ama ince',     'Kalitesi iyi fakat kışın tek başına ince kalıyor.',               9, 'published', 'tr', now() - INTERVAL '11 days'),
    (pid, 9009005, 4, 'Memnunum',           'Fiyatına göre başarılı, kargo hızlıydı.',                          5, 'published', 'tr', now() - INTERVAL '7 days'),
    (pid, 9009006, 3, 'İdare eder',         'Beklediğimden biraz dar kalıp, bir beden büyük alın.',             3, 'published', 'tr', now() - INTERVAL '4 days'),
    (pid, 9009007, 2, 'Beden sorunu',       'Görseldeki gibi durmadı, kol boyu kısa geldi.',                    1, 'published', 'tr', now() - INTERVAL '2 days')
  ON CONFLICT (product_id, user_id) DO UPDATE SET
    rating        = EXCLUDED.rating,
    title         = EXCLUDED.title,
    body          = EXCLUDED.body,
    helpful_count = EXCLUDED.helpful_count,
    created_at    = EXCLUDED.created_at;

  -- ── 3) Keep the product-level rating chip coherent with the seeded reviews. ─
  -- (PDP header reads products.rating_avg/rating_count; the reviews histogram is
  --  computed separately from product_reviews. Match them.)
  UPDATE catalog_schema.products
     SET rating_avg = sub.avg, rating_count = sub.cnt
    FROM (
      SELECT round(avg(rating)::numeric, 1) AS avg, count(*) AS cnt
        FROM catalog_schema.product_reviews WHERE product_id = pid
    ) sub
   WHERE id = pid;
END $$;

COMMIT;

-- walk-user-data.sql — idempotent dev seed for the logged-in walk user's
-- order/return history + coin balance + multi-seller catalog spread.
--
-- Run AFTER the API has created the user (id resolved by email_hash) + their
-- cart/favorites/addresses. DEV ONLY. Applied via:
--   docker exec -i postgres-ecom psql -U ecom_admin -d mopro_ecom < this  (orders/returns/sellers)
--   docker exec -i postgres-ledger psql -U ledger_admin -d mopro_ledger < (coin block, split below)
-- This file targets postgres-ecom; the coin block lives in walk-user-coin.sql.
--
-- Idempotency: every INSERT is guarded by a sentinel idempotency_key or a
-- NOT EXISTS / ON CONFLICT, so re-running is a no-op.

\set ON_ERROR_STOP on

-- ── Multi-seller spread ──────────────────────────────────────────────────────
-- All 50 seeded products belong to seller 1; move a handful to sellers 2 & 3 so
-- the cart/checkout "totals_by_seller" and PLP seller badges show >1 seller.
UPDATE catalog_schema.products SET seller_id = 2 WHERE id IN (2, 4) AND seller_id = 1;
UPDATE catalog_schema.products SET seller_id = 3 WHERE id IN (6, 9) AND seller_id = 1;

-- ── Order history (varied statuses) ──────────────────────────────────────────
-- One order per status the Orders surface renders: pending_payment, paid,
-- shipped, delivered, refunded. Each carries a single line off a real variant so
-- enrichOrderItems (GetVariantByID) resolves a title/price for the detail.
DO $$
DECLARE
  uid        BIGINT;
  ok         TEXT;
  oid        BIGINT;
  -- (variant_id, status, days_ago, set_delivered)
  rows       TEXT[][] := ARRAY[
                ['1','pending_payment','0','f'],
                ['3','paid','1','f'],
                ['5','shipped','3','f'],
                ['7','delivered','8','t'],
                ['4','delivered','12','t'],
                ['10','refunded','20','t']
              ];
  r          TEXT[];
  vprice     BIGINT;
  vseller    BIGINT;
  vcat       BIGINT;
  comm       BIGINT;
  kdv        BIGINT;
BEGIN
  SELECT id INTO uid FROM identity_schema.users WHERE email_verified = true ORDER BY id LIMIT 1;
  IF uid IS NULL THEN RAISE NOTICE 'no verified user; skipping orders'; RETURN; END IF;

  FOREACH r SLICE 1 IN ARRAY rows LOOP
    ok := 'walk-seed-order-' || r[1] || '-' || r[2];
    IF EXISTS (SELECT 1 FROM order_schema.orders WHERE idempotency_key = ok) THEN
      CONTINUE;
    END IF;
    SELECT v.price_minor, p.seller_id, p.category_id
      INTO vprice, vseller, vcat
      FROM catalog_schema.variants v JOIN catalog_schema.products p ON p.id = v.product_id
      WHERE v.id = r[1]::bigint;
    comm := round(vprice * 0.15);        -- 15% illustrative commission
    kdv  := round(comm   * 0.20);        -- 20% KDV on commission
    INSERT INTO order_schema.orders
      (user_id, status, subtotal_minor, shipping_minor, shipping_payer, total_minor,
       currency, market, delivered_at, cashback_eligible, cashback_currency,
       idempotency_key, seller_id, created_at, updated_at)
    VALUES
      (uid, r[2], vprice, 0, 'seller', vprice, 'TRY', 'TR',
       CASE WHEN r[4]='t' THEN now() - (r[3]||' days')::interval ELSE NULL END,
       true, 'TRY_COIN', ok, vseller,
       now() - (r[3]||' days')::interval, now() - (r[3]||' days')::interval)
    RETURNING id INTO oid;
    INSERT INTO order_schema.order_items
      (order_id, variant_id, seller_id, category_id, qty, unit_price_minor,
       unit_price_currency, commission_pct_bps, kdv_pct_bps, commission_amount_minor,
       kdv_amount_minor, seller_net_minor, list_unit_price_minor, basket_discount_pct)
    VALUES
      (oid, r[1]::bigint, vseller, vcat, 1, vprice, 'TRY', 1500, 2000, comm, kdv,
       vprice - comm - kdv, vprice, 0);
  END LOOP;
END $$;

-- ── Return history (varied statuses) ─────────────────────────────────────────
-- Returns reference the delivered + refunded orders. Statuses: pending, approved,
-- refunded — the three the İadelerim list + RT-06 filter render. Reset-and-insert
-- (delete this user's walk-seed returns first) keeps it deterministic + idempotent.
DO $$
DECLARE
  uid     BIGINT;
  delv    BIGINT[];           -- delivered order ids, ascending
  refd    BIGINT;             -- refunded order id
  -- (target order id, status, reason)
  plan    RECORD;
  oiid    BIGINT;
  price   BIGINT;
  rid     BIGINT;
  i       INT := 0;
BEGIN
  SELECT id INTO uid FROM identity_schema.users WHERE email_verified = true ORDER BY id LIMIT 1;
  IF uid IS NULL THEN RETURN; END IF;

  -- Reset prior walk-seed returns for this user (cascade clears items + history).
  DELETE FROM order_schema.returns
   WHERE user_id = uid AND description = 'Dev walk seed return';

  SELECT array_agg(id ORDER BY id) INTO delv
    FROM order_schema.orders WHERE user_id = uid AND status = 'delivered';
  SELECT id INTO refd
    FROM order_schema.orders WHERE user_id = uid AND status = 'refunded' ORDER BY id LIMIT 1;

  FOR plan IN
    SELECT * FROM (VALUES
      (delv[1], 'pending'::text,  'size_issue'::text),
      (delv[2], 'approved'::text, 'damaged'::text),
      (refd,    'refunded'::text, 'not_as_described'::text)
    ) AS t(oid, status, reason)
  LOOP
    CONTINUE WHEN plan.oid IS NULL;
    i := i + 1;
    SELECT id, unit_price_minor INTO oiid, price
      FROM order_schema.order_items WHERE order_id = plan.oid ORDER BY id LIMIT 1;
    INSERT INTO order_schema.returns
      (order_id, user_id, status, reason, description, refund_amount_minor,
       refund_currency, created_at, updated_at)
    VALUES
      (plan.oid, uid, plan.status, plan.reason, 'Dev walk seed return', price, 'TRY',
       now() - (i||' days')::interval, now() - (i||' days')::interval)
    RETURNING id INTO rid;
    INSERT INTO order_schema.return_items (return_id, order_id, order_item_id, quantity)
    VALUES (rid, plan.oid, oiid, 1)
    ON CONFLICT (order_id, order_item_id) DO NOTHING;
    INSERT INTO order_schema.return_status_history (return_id, status, note)
    VALUES (rid, plan.status, 'walk seed');
  END LOOP;
END $$;

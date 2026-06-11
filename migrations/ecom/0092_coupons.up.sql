-- 0092_coupons.up.sql
-- CT-03/CHK-04: seller-funded coupon discount (Salih-confirmed funding model).
-- A coupon is a cart/order-level percent discount applied ON TOP of the per-product
-- basket discount (CT-09), via the SAME per-unit snapshot path: the order build
-- lowers order_items.unit_price_minor, so commission/KDV/seller-net AND cashback all
-- compute on the coupon-discounted price (the snapshot does the work; fin-svc is
-- untouched; the capture ledger still balances). Seller-funded ⇒ NO new ledger
-- account, NO constitution change — exactly the CT-09 outcome.
--
-- v1 scope (§5 ship-simple-first): kind='percent' only. Fixed-amount coupons need
-- largest-remainder distribution across lines and are a documented follow-up.

-- The coupon catalogue. Owned by order_schema (the module that applies it); no
-- cross-schema reads. Codes are matched case-insensitively (UNIQUE on upper(code)).
CREATE TABLE IF NOT EXISTS order_schema.coupons (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code              TEXT      NOT NULL,
  kind              TEXT      NOT NULL DEFAULT 'percent'
                      CHECK (kind IN ('percent')),
  -- percent_off: whole percent in [1,100] for kind='percent'.
  percent_off       SMALLINT  NOT NULL
                      CHECK (percent_off >= 1 AND percent_off <= 100),
  min_basket_minor  BIGINT    NOT NULL DEFAULT 0 CHECK (min_basket_minor >= 0),
  -- NULL max_redemptions = unlimited.
  max_redemptions   INT       NULL CHECK (max_redemptions IS NULL OR max_redemptions >= 0),
  starts_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at        TIMESTAMPTZ NULL,
  active            BOOLEAN   NOT NULL DEFAULT TRUE,
  market            TEXT      NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Case-insensitive uniqueness per market (same code can exist in another market).
CREATE UNIQUE INDEX IF NOT EXISTS coupons_code_market_uniq
  ON order_schema.coupons (upper(code), market);

-- Redemption ledger: one row per (coupon, order). The UNIQUE makes the redemption
-- write idempotent (financial-core §4) — a retried capture cannot double-count.
-- order_id is a soft ref (BIGINT, no cross-schema FK; same schema here so a local
-- FK to orders is safe and used). coupon_id FK is in-schema.
CREATE TABLE IF NOT EXISTS order_schema.coupon_redemptions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coupon_id      BIGINT NOT NULL REFERENCES order_schema.coupons(id),
  order_id       BIGINT NOT NULL REFERENCES order_schema.orders(id),
  user_id        BIGINT NOT NULL,
  discount_minor BIGINT NOT NULL CHECK (discount_minor >= 0),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (coupon_id, order_id)
);

CREATE INDEX IF NOT EXISTS coupon_redemptions_coupon_idx
  ON order_schema.coupon_redemptions (coupon_id);

-- Order-level coupon audit columns (additive, backward-compatible).
--   coupon_code           → the applied code (NULL when none), for the summary line.
--   coupon_discount_minor → the coupon's slice of orders.discount_minor (the rest is
--                           the CT-09 basket discount). DEFAULT 0 keeps old rows valid.
ALTER TABLE order_schema.orders
  ADD COLUMN IF NOT EXISTS coupon_code           TEXT   NULL,
  ADD COLUMN IF NOT EXISTS coupon_discount_minor BIGINT NOT NULL DEFAULT 0
      CHECK (coupon_discount_minor >= 0);

-- Dev/test seed coupons (idempotent). Creation/admin is out of scope; these let the
-- cart/checkout flow exercise a real coupon. LOCAL/dev — harmless in prod (inactive
-- demo codes), but intended for the dev market TR.
INSERT INTO order_schema.coupons (code, kind, percent_off, min_basket_minor, market, expires_at)
VALUES
  ('WELCOME10', 'percent', 10,      0, 'TR', now() + interval '10 years'),
  ('SAVE20',    'percent', 20, 5000000, 'TR', now() + interval '10 years')  -- min 50.000,00 ₺ basket
ON CONFLICT (upper(code), market) DO NOTHING;

-- 65-order-schema.sql — order_schema.orders and order_schema.order_items tables.
-- order_schema itself is created in 20-schemas.sql.
-- order_schema.outbox is in 60-outbox.sql and must exist before this file runs.

CREATE TABLE IF NOT EXISTS order_schema.orders (
  id                BIGSERIAL    PRIMARY KEY,
  user_id           BIGINT       NOT NULL,
  status            TEXT         NOT NULL
                    CHECK (status IN ('pending_payment','paid','shipped','delivered',
                                      'cancelled','refunded','partially_refunded')),
  subtotal_minor    BIGINT       NOT NULL CHECK (subtotal_minor >= 0),
  shipping_minor    BIGINT       NOT NULL DEFAULT 0,
  shipping_payer    TEXT         NOT NULL DEFAULT 'buyer'
                    CHECK (shipping_payer IN ('buyer','seller','split','threshold_free')),
  total_minor       BIGINT       NOT NULL CHECK (total_minor >= 0),
  -- CT-09: Σ(list − discounted)×qty seller-funded basket discount; 0 = none.
  -- subtotal_minor is pre-discount, total_minor = subtotal_minor − discount_minor.
  discount_minor    BIGINT       NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
  currency          TEXT         NOT NULL,
  market            TEXT         NOT NULL DEFAULT 'TR',
  delivered_at      TIMESTAMPTZ,
  cashback_eligible BOOLEAN      NOT NULL DEFAULT TRUE,
  cashback_currency TEXT         NOT NULL DEFAULT 'TRY_COIN',
  idempotency_key   TEXT         NOT NULL UNIQUE,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_schema.order_items (
  id                       BIGSERIAL PRIMARY KEY,
  order_id                 BIGINT    NOT NULL REFERENCES order_schema.orders(id),
  variant_id               BIGINT    NOT NULL,
  seller_id                BIGINT    NOT NULL,
  category_id              BIGINT    NOT NULL,
  qty                      INTEGER   NOT NULL CHECK (qty > 0),
  -- unit_price_minor = the CHARGED (basket-discounted) unit; list_unit_price_minor
  -- is the pre-discount unit (= variant.price_minor) and basket_discount_pct the
  -- snapshotted whole-percent rate, kept for the strikethrough + "Sepette indirim"
  -- delta (CT-09). All downstream math derives from unit_price_minor.
  unit_price_minor         BIGINT    NOT NULL CHECK (unit_price_minor >= 0),
  list_unit_price_minor    BIGINT    NOT NULL DEFAULT 0 CHECK (list_unit_price_minor >= 0),
  basket_discount_pct      SMALLINT  NOT NULL DEFAULT 0
                           CHECK (basket_discount_pct >= 0 AND basket_discount_pct <= 100),
  unit_price_currency      TEXT      NOT NULL,
  commission_pct_bps       INTEGER   NOT NULL,
  kdv_pct_bps              INTEGER   NOT NULL,
  commission_amount_minor  BIGINT    NOT NULL CHECK (commission_amount_minor >= 0),
  kdv_amount_minor         BIGINT    NOT NULL CHECK (kdv_amount_minor >= 0),
  seller_net_minor         BIGINT    NOT NULL CHECK (seller_net_minor >= 0)
);

CREATE INDEX IF NOT EXISTS orders_user_idx
    ON order_schema.orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_status_idx
    ON order_schema.orders(status);
CREATE INDEX IF NOT EXISTS orders_delivered_idx
    ON order_schema.orders(delivered_at)
    WHERE delivered_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS order_items_order_idx
    ON order_schema.order_items(order_id);

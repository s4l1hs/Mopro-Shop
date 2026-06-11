-- 0091_order_basket_discount.up.sql
-- CT-09: make the seller-funded "Sepette %X İndirim" (products.basket_discount_pct,
-- #133/0087) a CHARGED discount. The order build now snapshots the discounted unit
-- price into order_items.unit_price_minor (the base every downstream consumer —
-- cashback, orderledger, sellerpayout, returns — already derives from), so the
-- discount propagates with no fin-svc change and the capture ledger still balances.
--
-- These additive columns preserve the audit trail (list price + applied rate) and
-- expose the order-level discount for the "Sepette indirim" summary line:
--   * order_items.list_unit_price_minor → the pre-discount unit (= variant.price_minor),
--     for the strikethrough + the per-line discount delta.
--   * order_items.basket_discount_pct   → the snapshotted whole-percent rate.
--   * orders.discount_minor             → Σ(list − discounted)×qty (the summary line).
--
-- All DEFAULT 0 and backward-compatible: existing rows + non-discounted orders keep
-- discount_minor = 0 and subtotal_minor == total_minor (no behavior change). Existing
-- order_items are backfilled so list_unit_price_minor == unit_price_minor (no
-- historical discount). ADD COLUMN ... DEFAULT is a fast metadata-only change in PG16.

ALTER TABLE order_schema.order_items
  ADD COLUMN IF NOT EXISTS list_unit_price_minor BIGINT  NOT NULL DEFAULT 0
      CHECK (list_unit_price_minor >= 0),
  ADD COLUMN IF NOT EXISTS basket_discount_pct   SMALLINT NOT NULL DEFAULT 0
      CHECK (basket_discount_pct >= 0 AND basket_discount_pct <= 100);

-- Backfill: pre-CT-09 rows had no basket discount → list price == charged price.
UPDATE order_schema.order_items
  SET list_unit_price_minor = unit_price_minor
  WHERE list_unit_price_minor = 0 AND unit_price_minor > 0;

ALTER TABLE order_schema.orders
  ADD COLUMN IF NOT EXISTS discount_minor BIGINT NOT NULL DEFAULT 0
      CHECK (discount_minor >= 0);

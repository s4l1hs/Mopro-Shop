-- 0103_return_item_reasons.up.sql — RT-05: per-item return reasons.
--
-- The return flow collects a per-item reason + note, but the contract folded them
-- to the header reason (first item) + description. Surface per-line reasons by
-- carrying reason+note on each return_items row. Additive; the header
-- order_schema.returns.reason stays (the dominant/first reason, backward compat).
-- reason is nullable — a line may omit it and fall back to the header reason
-- (e.g. full-order returns). IDEMPOTENT.

ALTER TABLE order_schema.return_items
    ADD COLUMN IF NOT EXISTS reason TEXT
        CHECK (reason IS NULL OR reason IN ('wrong_product','not_as_described',
                                            'damaged','size_issue','changed_mind','other')),
    ADD COLUMN IF NOT EXISTS note   TEXT NOT NULL DEFAULT '';

-- 0083_variant_price_history.up.sql — P-030 (TR 6502 / EU Omnibus 2019/2161)
-- Tracks every variant price-set so the "lowest price in the last 30 days" can be
-- shown alongside a price reduction. Mechanism B (trigger): an AFTER INSERT OR
-- UPDATE trigger on catalog_schema.variants records a row on every price change,
-- capturing seed-, app-, and any future import/update writes uniformly (the Go
-- InsertVariant path does not even set original_price_minor — see
-- docs/internal/p030-price-history-architecture.md).

CREATE TABLE IF NOT EXISTS catalog_schema.variant_price_history (
    id                   BIGSERIAL   PRIMARY KEY,
    variant_id           BIGINT      NOT NULL,   -- soft ref (CLAUDE.md §5 discipline)
    product_id           BIGINT      NOT NULL,   -- denormalized for the per-product MIN query
    price_minor          BIGINT      NOT NULL CHECK (price_minor >= 0),
    original_price_minor BIGINT,                 -- strikethrough "was" price at this point (null = none)
    currency             TEXT        NOT NULL DEFAULT 'TRY',
    source               TEXT        NOT NULL DEFAULT 'trigger',  -- 'create' | 'update' | 'backfill'
    effective_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Serves the "MIN(price_minor) WHERE product_id = ? AND effective_at >= now()-30d" read.
CREATE INDEX IF NOT EXISTS vph_product_effective_idx
    ON catalog_schema.variant_price_history(product_id, effective_at DESC);

-- Mechanism B: record a history row whenever a variant's price is set or changes.
-- IS DISTINCT FROM keeps a no-op UPDATE (same values) from duplicating a row.
CREATE OR REPLACE FUNCTION catalog_schema.track_variant_price() RETURNS trigger AS $$
BEGIN
    IF (TG_OP = 'INSERT')
       OR (NEW.price_minor          IS DISTINCT FROM OLD.price_minor)
       OR (NEW.original_price_minor IS DISTINCT FROM OLD.original_price_minor) THEN
        INSERT INTO catalog_schema.variant_price_history
            (variant_id, product_id, price_minor, original_price_minor, currency, source)
        VALUES (NEW.id, NEW.product_id, NEW.price_minor, NEW.original_price_minor, NEW.price_currency,
                CASE WHEN TG_OP = 'INSERT' THEN 'create' ELSE 'update' END);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS variants_price_history_trg ON catalog_schema.variants;
CREATE TRIGGER variants_price_history_trg
    AFTER INSERT OR UPDATE OF price_minor, original_price_minor
    ON catalog_schema.variants
    FOR EACH ROW EXECUTE FUNCTION catalog_schema.track_variant_price();

-- Backfill: one baseline row per existing variant so lowest_30d is computable from
-- migration day. The backfill IS the lowest known price until prices begin to move.
INSERT INTO catalog_schema.variant_price_history
    (variant_id, product_id, price_minor, original_price_minor, currency, source, effective_at)
SELECT id, product_id, price_minor, original_price_minor, price_currency, 'backfill', now()
FROM catalog_schema.variants;

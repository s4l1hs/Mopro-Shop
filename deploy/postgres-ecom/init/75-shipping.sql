-- 75-shipping.sql — shipping_schema: shipments + shipment_events
-- Phase 1.6: kargo adapter layer. "delivered" state is the source of truth for
-- delivered_at which starts the 3-business-day cashback + payout unlock clock.
-- CLAUDE.md § 3.1, ARCHITECTURE.md § 8.4.

CREATE SCHEMA IF NOT EXISTS shipping_schema;

GRANT USAGE ON SCHEMA shipping_schema TO ecom_admin;
GRANT ALL   ON ALL TABLES    IN SCHEMA shipping_schema TO ecom_admin;
GRANT ALL   ON ALL SEQUENCES IN SCHEMA shipping_schema TO ecom_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA shipping_schema
    GRANT ALL ON TABLES    TO ecom_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA shipping_schema
    GRANT ALL ON SEQUENCES TO ecom_admin;

CREATE TABLE shipping_schema.shipments (
    id                    BIGSERIAL    PRIMARY KEY,
    order_id              BIGINT       NOT NULL,
    -- No FK to order_schema.orders: cross-schema FK forbidden (CLAUDE.md § 5).
    carrier               TEXT         NOT NULL,
    -- 'aras' | 'yurtici' | 'surat' | 'mng' | 'hepsijet' | 'ptt'
    tracking_number       TEXT,
    carrier_shipment_id   TEXT,
    state                 TEXT         NOT NULL DEFAULT 'pending'
                          CHECK (state IN ('pending','picked_up','in_transit',
                                           'out_for_delivery','delivered',
                                           'returned','cancelled','failed')),
    label_pdf_b2_key      TEXT,
    estimated_delivery_at TIMESTAMPTZ,
    delivered_at          TIMESTAMPTZ,
    last_polled_at        TIMESTAMPTZ,
    idempotency_key       TEXT         NOT NULL,
    cost_minor            BIGINT,
    cost_currency         TEXT,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_shipments_idempotency UNIQUE (idempotency_key)
);

-- Partial unique: carrier+tracking pair is unique once tracking_number is set.
-- NULL tracking_number allowed before label creation.
CREATE UNIQUE INDEX uq_shipments_tracking
    ON shipping_schema.shipments (carrier, tracking_number)
    WHERE tracking_number IS NOT NULL;

CREATE TABLE shipping_schema.shipment_events (
    id          BIGSERIAL    PRIMARY KEY,
    shipment_id BIGINT       NOT NULL
                REFERENCES shipping_schema.shipments(id),
    state       TEXT         NOT NULL,
    source      TEXT         NOT NULL
                CHECK (source IN ('webhook','poll','api')),
    carrier_raw JSONB,
    event_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Supporting indexes
CREATE INDEX idx_shipments_order_id
    ON shipping_schema.shipments (order_id);

-- Partial index for poll queries: only active (non-terminal) states
CREATE INDEX idx_shipments_poll
    ON shipping_schema.shipments (carrier, last_polled_at)
    WHERE state IN ('pending','picked_up','in_transit','out_for_delivery');

CREATE INDEX idx_shipment_events_shipment
    ON shipping_schema.shipment_events (shipment_id);

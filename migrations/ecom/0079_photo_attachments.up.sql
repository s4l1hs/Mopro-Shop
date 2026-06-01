-- 0079_photo_attachments.up.sql — shared photo-upload infra (reviews + returns).
-- Lives in attachments_schema (owned by the attachments module, core-svc). `uploaded_by_user_id` and
-- `entity_id` are plain BIGINT soft references (no cross-schema FK to
-- identity_schema.users, catalog_schema.product_reviews, or
-- order_schema.return_items) per CLAUDE.md § 5 + the CONTRIBUTING soft-reference
-- pattern. entity_id IS NULL = uploaded-but-not-yet-attached (orphan, in flight
-- during a multi-step submission); the cleanup job (Backlog) deletes orphans
-- older than 24h.

CREATE SCHEMA IF NOT EXISTS attachments_schema;

CREATE TABLE IF NOT EXISTS attachments_schema.photo_attachments (
    id                  BIGSERIAL   PRIMARY KEY,
    storage_key         TEXT        NOT NULL UNIQUE,   -- bucket-relative object key
    content_type        TEXT        NOT NULL,          -- sniffed MIME (not client-claimed)
    byte_size           INTEGER     NOT NULL,
    width_px            INTEGER,
    height_px           INTEGER,
    uploaded_by_user_id BIGINT      NOT NULL,          -- soft ref → identity_schema.users
    entity_type         TEXT        NOT NULL,          -- 'review' | 'return_item'
    entity_id           BIGINT,                        -- soft ref; NULL = orphan (unattached)
    sort_order          INTEGER     NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Read path: photos for an entity, in display order.
CREATE INDEX IF NOT EXISTS idx_photo_attachments_entity
    ON attachments_schema.photo_attachments (entity_type, entity_id, sort_order);

-- Orphan-cleanup path: unattached uploads by age (Backlog cleanup job).
CREATE INDEX IF NOT EXISTS idx_photo_attachments_orphan
    ON attachments_schema.photo_attachments (uploaded_by_user_id, created_at)
    WHERE entity_id IS NULL;

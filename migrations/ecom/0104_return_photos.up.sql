-- 0104_return_photos.up.sql — RT-03: return evidence photos.
--
-- Damage / wrong-item evidence attached to a return request. Photos are uploaded
-- via the existing POST /uploads/photos pipeline (gated by STORAGE_ENABLED); the
-- return API stores only the resulting storage KEYS (not raw bytes) and serves
-- CDN urls on read (mediaurl.CDNUrl). One row per photo, ordered by sort_rank.
-- IDEMPOTENT. NOTE: the buyer-side photo CAPTURE step (mobile picker + upload) is
-- deferred to the storage-provisioning gate (docs/internal/returns-batch.md);
-- this table + the backend read/write are ready for it.

CREATE TABLE IF NOT EXISTS order_schema.return_photos (
    id         BIGSERIAL   PRIMARY KEY,
    return_id  BIGINT      NOT NULL REFERENCES order_schema.returns(id) ON DELETE CASCADE,
    photo_key  TEXT        NOT NULL,
    sort_rank  INT         NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS return_photos_return_idx
    ON order_schema.return_photos (return_id, sort_rank);

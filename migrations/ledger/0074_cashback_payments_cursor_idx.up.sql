-- Migration 74: composite index on cashback_schema.payments(plan_id, id DESC)
-- Enables efficient cursor-paginated listing of payments per plan in the
-- GET /v1/cashback/plans/{id}/payments HTTP endpoint.
CREATE INDEX IF NOT EXISTS cashback_payments_plan_id_idx
    ON cashback_schema.payments (plan_id, id DESC);

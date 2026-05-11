-- 50-cashback-schema.sql — v6 PERPETUAL cashback schema.
-- Source: DATA_DICTIONARY.md § 8 verbatim.
--
-- v6 differences from fixed-term (v5):
--   NO total_amount_minor  — no finite obligation; plan is open-ended
--   NO total_months        — perpetual; payments never stop until cancellation
--   NO end_date            — perpetual
--   YES monthly_amount_minor + reference_interest_rate_bps (frozen at 5000 = %50 per plan)
--   YES start_date = delivered_at + 3 business days (first instalment unlock)
--
-- plans rows are IMMUTABLE after creation except for `status`.
-- The one exception — monthly_amount_minor on partial refund — requires a plans_history
-- audit entry in the same transaction (enforced by 51-cashback-immutable-trigger.sql).

CREATE TABLE cashback_schema.plans (
  id                          BIGSERIAL PRIMARY KEY,
  order_id                    BIGINT NOT NULL,                              -- denormalized; no FK across cluster
  user_id                     BIGINT NOT NULL,
  monthly_amount_minor        BIGINT NOT NULL CHECK (monthly_amount_minor > 0),
  currency                    TEXT NOT NULL DEFAULT 'TRY_COIN',
  reference_interest_rate_bps INTEGER NOT NULL DEFAULT 5000
    CHECK (reference_interest_rate_bps BETWEEN 1 AND 20000),               -- 5000 = %50.00, snapshotted
  start_date                  DATE NOT NULL,                               -- = delivered_at + 3 business days
  -- NO end_date — plan is perpetual.
  status                      TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','cancelled','suspended')),
  delivered_at                TIMESTAMPTZ NOT NULL,
  market                      TEXT NOT NULL DEFAULT 'TR',
  commission_snapshot         JSONB NOT NULL,                              -- per-item commission breakdown (audit)
  idempotency_key             TEXT NOT NULL UNIQUE,                        -- 'cashback:plan:order_<order_id>'
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX cashback_plans_user_idx     ON cashback_schema.plans(user_id, status);
CREATE INDEX cashback_plans_order_idx    ON cashback_schema.plans(order_id);
CREATE INDEX cashback_plans_active_due_idx ON cashback_schema.plans(start_date)
    WHERE status = 'active';

-- Audit trail for partial-refund monthly_amount_minor changes.
-- The mopro cashback partial-refund CLI inserts here BEFORE updating plans.monthly_amount_minor
-- (within the same transaction — required by the immutability trigger's 2-second window check).
CREATE TABLE cashback_schema.plans_history (
  id            BIGSERIAL PRIMARY KEY,
  plan_id       BIGINT NOT NULL REFERENCES cashback_schema.plans(id),
  field_changed TEXT NOT NULL,
  old_value     TEXT NOT NULL,
  new_value     TEXT NOT NULL,
  reason        TEXT NOT NULL,
  changed_by    TEXT NOT NULL,                                             -- 'cli:partial-refund' | 'admin'
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Monthly cron-appended payment rows. No pre-seeded rows (perpetual model).
-- Cron idempotency: UNIQUE (plan_id, period_yyyymm) prevents double-payment for any given month.
CREATE TABLE cashback_schema.payments (
  id                    BIGSERIAL PRIMARY KEY,
  plan_id               BIGINT NOT NULL REFERENCES cashback_schema.plans(id),
  period_yyyymm         INTEGER NOT NULL
    CHECK (period_yyyymm BETWEEN 202600 AND 209912),
  scheduled_date        DATE NOT NULL,
  paid_date             DATE,
  amount_minor          BIGINT NOT NULL CHECK (amount_minor > 0),
  status                TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','paid','failed','cancelled')),
  ledger_transaction_id BIGINT,                                            -- wallet_schema.transactions(id) when paid
  idempotency_key       TEXT NOT NULL UNIQUE,                              -- 'cashback:plan_<id>:period_<yyyymm>'
  attempt_count         INTEGER NOT NULL DEFAULT 0,
  last_attempt_at       TIMESTAMPTZ,
  last_error            TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX cashback_payments_plan_period_uq
    ON cashback_schema.payments(plan_id, period_yyyymm);
CREATE INDEX cashback_payments_due_idx
    ON cashback_schema.payments(scheduled_date, status) WHERE status = 'scheduled';

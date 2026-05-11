-- 51-cashback-immutable-trigger.sql — cashback plan immutability enforcement.
-- Source: DATA_DICTIONARY.md § 8 verbatim (baseline).
-- v0.3-enhanced beyond DATA_DICTIONARY.md baseline: additional belt-and-suspenders
-- guards on user_id, market, commission_snapshot, idempotency_key approved at Phase 0.3.

CREATE OR REPLACE FUNCTION cashback_schema.enforce_plan_immutable()
RETURNS TRIGGER AS $$
BEGIN
    -- monthly_amount_minor is mutable ONLY via the mopro cashback partial-refund CLI,
    -- which atomically INSERTs a plans_history row then UPDATEs monthly_amount_minor
    -- in the SAME transaction (2-second window is always satisfied within one txn).
    IF OLD.monthly_amount_minor != NEW.monthly_amount_minor THEN
        IF NOT EXISTS (
            SELECT 1 FROM cashback_schema.plans_history
            WHERE plan_id = OLD.id
              AND created_at > now() - interval '2 seconds'
        ) THEN
            RAISE EXCEPTION 'monthly_amount_minor mutation requires plans_history entry (partial refund only)';
        END IF;
    END IF;

    -- Baseline locked fields (DATA_DICTIONARY.md § 8 verbatim):
    IF OLD.start_date                  != NEW.start_date
       OR OLD.currency                 != NEW.currency
       OR OLD.reference_interest_rate_bps != NEW.reference_interest_rate_bps
       OR OLD.delivered_at             != NEW.delivered_at
       OR OLD.order_id                 != NEW.order_id
    -- v0.3-enhanced: additional locked fields beyond DATA_DICTIONARY.md baseline:
       OR OLD.user_id                  != NEW.user_id
       OR OLD.market                   != NEW.market
       OR OLD.commission_snapshot::text != NEW.commission_snapshot::text
       OR OLD.idempotency_key          != NEW.idempotency_key
    THEN
        RAISE EXCEPTION 'cashback plan core fields are immutable';
    END IF;

    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER cashback_plan_immutable_trg
BEFORE UPDATE ON cashback_schema.plans
FOR EACH ROW EXECUTE FUNCTION cashback_schema.enforce_plan_immutable();

-- 61-seller-payout-immutable-trigger.sql — seller payout immutability enforcement.
-- Source: DATA_DICTIONARY.md § 9 verbatim (baseline).
-- v0.3-enhanced beyond DATA_DICTIONARY.md baseline: additional belt-and-suspenders
-- guards on delivered_at and idempotency_key approved at Phase 0.3.

CREATE OR REPLACE FUNCTION commission_schema.enforce_payout_immutable()
RETURNS TRIGGER AS $$
BEGIN
    -- Baseline locked fields (DATA_DICTIONARY.md § 9 verbatim):
    IF OLD.amount_minor   != NEW.amount_minor
       OR OLD.unlock_at   != NEW.unlock_at
       OR OLD.currency    != NEW.currency
       OR OLD.order_id    != NEW.order_id
       OR OLD.seller_id   != NEW.seller_id
    -- v0.3-enhanced: additional locked fields beyond DATA_DICTIONARY.md baseline:
       OR OLD.delivered_at     != NEW.delivered_at
       OR OLD.idempotency_key  != NEW.idempotency_key
    THEN
        RAISE EXCEPTION 'seller_payout core fields are immutable; create reversal instead';
    END IF;

    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER seller_payout_immutable_trg
BEFORE UPDATE ON commission_schema.seller_payouts
FOR EACH ROW EXECUTE FUNCTION commission_schema.enforce_payout_immutable();

-- 66-sellerpayout-grants.sql — explicit grants for sellerpayout_user on phase 2.3 tables.
--
-- ALTER DEFAULT PRIVILEGES in 30-grants.sql covers tables created in
-- sellerpayout_schema, but only applies to tables created AFTER the GRANT was
-- issued. Belt-and-suspenders: explicit grants on tables created in 62–64.
--
-- sellerpayout_user also needs INSERT on wallet_schema.ledger_alerts for fraud-hold
-- and ambiguous-transfer escalation.

-- sellerpayout_schema tables
GRANT SELECT, INSERT, UPDATE ON sellerpayout_schema.payout_batches         TO sellerpayout_user;
GRANT USAGE, SELECT ON SEQUENCE sellerpayout_schema.payout_batches_id_seq  TO sellerpayout_user;

GRANT SELECT, INSERT ON sellerpayout_schema.seller_psp_accounts            TO sellerpayout_user;
GRANT USAGE, SELECT ON SEQUENCE sellerpayout_schema.seller_psp_accounts_id_seq TO sellerpayout_user;

-- wallet_schema.ledger_alerts: write access for escalation events
GRANT USAGE ON SCHEMA wallet_schema                                       TO sellerpayout_user;
GRANT SELECT, INSERT ON wallet_schema.ledger_alerts                       TO sellerpayout_user;

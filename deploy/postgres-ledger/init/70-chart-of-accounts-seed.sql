-- 70-chart-of-accounts-seed.sql — pre-seed platform-level chart of accounts.
-- Source: LEDGER_GUIDE.md § 2 (v6 perpetual model).
--
-- Only PLATFORM accounts are seeded here. All status='active', owner_type='platform', owner_id=NULL.
-- Idempotent via the partial unique index accounts_platform_type_currency_uq (defined in 40-wallet-schema.sql).
--
-- NOT seeded here (lazy-created at runtime by wallet module):
--   liability:wallet:user_<id>:TRY_COIN  — per-user coin wallet
--     → created by wallet.OpenOrFindUserWallet(ctx, userID, currency) on first cashback payment
--
--   liability:seller_payable:TRY          — per-seller pending net payout account (OQ2 decision)
--     → created lazily by wallet.FindOrOpenSellerPayable(ctx, sellerID, currency) at first payout
--     → NOT a single pool account; each seller gets their own payable account
--
-- Naming convention: type = '<account_class>:<subclass>[:<subclass>]' (without currency suffix).
-- Full logical name = type + ':' + currency, e.g. 'asset:bank:escrow:TRY'.

INSERT INTO wallet_schema.accounts (type, owner_type, owner_id, currency, status) VALUES

  -- Assets: real fiat held in PSP escrow or staged for outbound transfer
  ('asset:bank:escrow',           'platform', NULL, 'TRY',      'active'),
  ('asset:bank:outbound_pending', 'platform', NULL, 'TRY',      'active'),

  -- Liabilities: pending obligations to external parties
  ('liability:bank_outbound',     'platform', NULL, 'TRY',      'active'),
  ('liability:kdv_payable',       'platform', NULL, 'TRY',      'active'),

  -- Equity: Mopro's permanent capital (commission principal — NEVER repaid)
  ('equity:retained_commission',  'platform', NULL, 'TRY',      'active'),

  -- Equity: float yield from 3-business-day escrow window (monthly recognition by Treasury)
  ('equity:retained_float_income','platform', NULL, 'TRY',      'active'),

  -- Equity: realized FX P&L from coin↔fiat conversions
  ('equity:fx_gain_loss',         'platform', NULL, 'TRY',      'active'),

  -- Equity (TRY_COIN): counter-equity debited each monthly cashback cron payment.
  -- v6 perpetual model: NO upfront provision; each month's coin issuance is recognized as it is paid.
  ('equity:cashback_distribution','platform', NULL, 'TRY_COIN', 'active'),

  -- Equity (TRY_COIN): counter-equity debited each refund settlement (RT-01,
  -- refund-as-coin). Recognized per-settlement, no upfront provision — the exact
  -- analogue of cashback_distribution. Migration: 0082_refund_distribution_account.
  ('equity:refund_distribution',  'platform', NULL, 'TRY_COIN', 'active')

ON CONFLICT DO NOTHING;

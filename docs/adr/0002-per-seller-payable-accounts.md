# ADR 0002: Per-Seller Payable Accounts (Lazy-Created, No Pool)

- **Status:** Accepted
- **Date:** 2026-05-11
- **Phase introduced:** Phase 0 (Prompt 0.3)
- **Decided by:** Mopro architecture
- **Related:** LEDGER_GUIDE.md § 2, § 8.2

## Context
The `liability:seller_payable:<CUR>` account class represents pending net payouts to sellers (3 business days after delivered_at). LEDGER_GUIDE.md § 2 originally listed this as a single platform-pool account. However, LEDGER_GUIDE.md § 8.2 calls `wallet.FindOrOpenSellerPayable(ctx, p.SellerID, p.Currency)`, whose signature unambiguously indicates per-seller granularity.

We must reconcile this and pick one model.

## Decision
Per-seller, lazy-created accounts. Each seller gets their own `liability:seller_payable:<CUR>:seller_<id>` account when they receive their first payable balance, via `wallet.FindOrOpenSellerPayable`. The platform pool concept is REJECTED.

The pre-seed in `70-chart-of-accounts-seed.sql` does NOT create any seller_payable accounts.

## Consequences

### Positive
- Per-seller balance queries are O(1) (one account, one row in materialized view)
- Reconciliation against PSP transfer history is trivially per-seller
- Dispute resolution uses one canonical account per seller
- Aligns with `seller_id` partitioning in audit logs

### Negative
- More rows in `wallet_schema.accounts` (one per active seller); at 100K sellers + 5 currencies = 500K account rows. Acceptable; PG handles tens of millions easily
- Cannot read aggregate "total seller_payable" without summing across all seller accounts. Mitigated by an aggregate VIEW added in Phase 2

### Mitigations
- Phase 2.1 adds an aggregate VIEW: `wallet_schema.seller_payable_totals` for treasury reporting
- Account creation is lazy and idempotent (UNIQUE constraint on `(type, currency, owner_type, owner_id)`)

## Alternatives Considered
1. **Single platform pool** (the original LEDGER_GUIDE.md § 2 listing) — rejected: aggregate-only loses per-seller granularity needed for dispute resolution, marketplace-level reconciliation, and per-seller withdrawal eligibility checks
2. **Per-seller PER-ORDER accounts** — rejected: cardinality explosion (millions of accounts within months)

## Revisit
Never (core architecture). This decision shapes the entire Treasury and Seller Payout modules.

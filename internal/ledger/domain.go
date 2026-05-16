// Package ledger defines shared double-entry ledger types used by fin-svc.
// All amounts use integer minor units (BIGINT). No float types permitted.
package ledger

// PostInput is the command for a single ledger transaction.
// All Entries in one PostInput MUST reference accounts of the same Currency.
// The DB trigger enforces D=C and single-currency at COMMIT; the wallet
// service additionally validates defensively before touching the DB.
type PostInput struct {
	Type           string // e.g. 'cashback_payment', 'seller_payout', 'commission_accrual'
	Reference      string // free-text human reference stored in transactions.reference
	FxPairID       string // non-empty only for FX two-leg transactions
	IdempotencyKey string // MANDATORY. Maps to transactions.idempotency_key UNIQUE.
	Market         string // ISO-3166 alpha-2 (e.g. 'TR')
	Currency       string // MANDATORY. Single currency for ALL Entries.
	Entries        []Entry
}

// Entry is one debit or credit line within a PostInput.
type Entry struct {
	AccountID   int64          // wallet_schema.accounts.id; account.currency MUST equal PostInput.Currency
	Direction   EntryDirection // 'D' (debit) or 'C' (credit)
	AmountMinor int64          // MUST be > 0; stored as BIGINT in ledger_entries
}

// Transaction is the row inserted into wallet_schema.transactions.
// It is constructed internally by the wallet repository; callers only supply PostInput.
type Transaction struct {
	Type           string
	Reference      string
	FxPairID       string
	IdempotencyKey string
}

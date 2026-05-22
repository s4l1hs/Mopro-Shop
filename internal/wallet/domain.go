package wallet

import "time"

// Account is the in-memory representation of a wallet_schema.accounts row.
type Account struct {
	ID        int64
	Type      string
	OwnerType string
	OwnerID   *int64 // NULL for platform accounts
	Currency  string
	Status    string
	CreatedAt time.Time
}

// LedgerEntryRow is a read projection of wallet_schema.ledger_entries
// joined with wallet_schema.transactions. Used by the HTTP read path only.
type LedgerEntryRow struct {
	ID           int64
	AmountMinor  int64
	Direction    string // "D" (debit) or "C" (credit) from the account's perspective
	TxnType      string // transaction type, e.g. "cashback_payment"
	TxnReference string // transactions.reference; empty when not set
	CreatedAt    time.Time
}

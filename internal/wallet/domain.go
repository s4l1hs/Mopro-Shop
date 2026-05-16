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

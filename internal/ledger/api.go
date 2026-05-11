// Package ledger defines shared double-entry ledger types used by fin-svc.
// All amounts use integer minor units (BIGINT). No float types permitted.
package ledger

// EntryDirection represents a ledger entry direction.
type EntryDirection string

const (
	// Debit decreases asset/expense accounts and increases liability/equity accounts.
	Debit EntryDirection = "D"
	// Credit increases asset/expense accounts and decreases liability/equity accounts.
	Credit EntryDirection = "C"
)

// Service defines the ledger write interface for fin-svc modules.
type Service interface{}

// Repository defines the storage interface for ledger tables.
type Repository interface{}

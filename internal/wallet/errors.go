package wallet

import "errors"

var (
	// ErrIdempotencyKeyRequired is returned when PostInput.IdempotencyKey is empty.
	ErrIdempotencyKeyRequired = errors.New("wallet: idempotency_key is required")

	// ErrInvalidAmount is returned when any entry has AmountMinor ≤ 0 or fewer
	// than 2 entries are supplied.
	ErrInvalidAmount = errors.New("wallet: invalid amount")

	// ErrCurrencyRequired is returned when PostInput.Currency is empty.
	ErrCurrencyRequired = errors.New("wallet: currency is required")

	// ErrCurrencyMismatch is returned by the defensive pre-check when an entry
	// references an account whose stored currency differs from PostInput.Currency.
	// The DB trigger (enforce_double_entry) would also catch this at COMMIT but
	// with a raw check_violation; this error gives a typed, readable alternative.
	ErrCurrencyMismatch = errors.New("wallet: currency mismatch in entries")

	// ErrAccountNotFound is returned by FindAccount / FindAccountByType /
	// FindAccountByOwner when no matching account exists.
	ErrAccountNotFound = errors.New("wallet: account not found")

	// ErrInsufficientBalance is reserved for Phase 3 (withdrawal critical path).
	ErrInsufficientBalance = errors.New("wallet: insufficient balance")

	// ErrMaxRetriesExceeded is returned by WithTx after exhausting SERIALIZABLE
	// retry attempts (pgError 40001 — serialization failure).
	ErrMaxRetriesExceeded = errors.New("wallet: exceeded serialization retry limit")
)

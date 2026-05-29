// Package commission manages commission accruals and settlements (fin-svc).
//
// Currently the package owns `commission_schema.capture_postings` — the
// append-only audit table that records every PSP-capture's commission
// split. Consumers (today: orderledger) depend on the `CaptureRecorder`
// interface; the concrete pgx-backed implementation lives in
// `capture_recorder.go` and is constructed via `NewCaptureRecorder`.
//
// Future commission functionality (refunds, partial captures, period
// closes) should land here and follow the same interface-first pattern so
// other modules never reach into `commission_schema` directly. The
// `make boundaries` regression guard enforces this from the outside.
package commission

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// Service defines the public interface of the commission module.
// Reserved for future commission orchestration (refunds, period closes).
type Service interface{}

// Repository defines the storage interface of the commission module.
// Reserved for future commission domain reads beyond the capture-posting
// audit trail.
type Repository interface{}

// CaptureRecorder is the seam through which other modules persist and
// read back capture-posting audit rows. orderledger.Service depends on
// this interface; the concrete pgx-backed implementation is private
// (pgRecorder in capture_recorder.go) and constructed via
// NewCaptureRecorder.
//
// All methods are safe to call from inside a SERIALIZABLE transaction
// (InsertCapturePosting takes the active tx; FindCapturePostingByOrderID
// reads from the underlying pool — the caller is expected to use it as
// a fast pre-check before opening the transaction).
type CaptureRecorder interface {
	// InsertCapturePosting writes a capture_postings audit row within tx.
	// Returns ErrAlreadyPosted on UNIQUE(order_id) conflict — idempotent
	// re-delivery of an order.paid event.
	InsertCapturePosting(ctx context.Context, tx pgx.Tx, p CapturePosting) error

	// FindCapturePostingByOrderID returns the existing posting for an
	// order_id, or (nil, nil) when none exists. Used as a fast idempotency
	// pre-check before opening an expensive SERIALIZABLE transaction; the
	// UNIQUE(order_id) constraint on the table is the second guard.
	FindCapturePostingByOrderID(ctx context.Context, orderID int64) (*CapturePosting, error)
}

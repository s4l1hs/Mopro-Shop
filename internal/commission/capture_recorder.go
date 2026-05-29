package commission

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrAlreadyPosted is returned by InsertCapturePosting when a capture_postings
// row already exists for the order (UNIQUE order_id constraint).
//
// Moved here from internal/orderledger as part of the commission-owns-its-
// schema refactor: commission_schema.capture_postings is commission-domain
// data; orderledger now writes through the CaptureRecorder seam instead of
// reaching across the schema boundary directly.
var ErrAlreadyPosted = errors.New("commission: capture posting already recorded")

// CapturePosting is the audit row in commission_schema.capture_postings.
// One row per paid order; UNIQUE(order_id) enforces idempotency at the DB.
//
// Fields are denormalized snapshots — the upstream order.paid event carries
// item-level frozen commission/KDV/seller-net values, which orderledger
// aggregates and hands to the recorder. The recorder is purely an append-
// only persistence layer; it does NOT compute or look up live commission
// rates.
type CapturePosting struct {
	ID              int64
	OrderID         int64
	TransactionID   int64
	IdempotencyKey  string
	GrossMinor      int64
	SellerNetMinor  int64
	CommissionMinor int64
	KdvMinor        int64
	ShippingMinor   int64
	Currency        string
	Market          string
	Status          string // 'posted'
	CreatedAt       time.Time
}

// pgRecorder is the pgx-backed concrete implementation of CaptureRecorder.
// Constructed via NewCaptureRecorder; consumers depend on the interface,
// not this type.
type pgRecorder struct {
	pool *pgxpool.Pool
}

// NewCaptureRecorder constructs the pgx-backed recorder. Returns the
// CaptureRecorder interface so callers depend on the seam, not the
// concrete type.
func NewCaptureRecorder(pool *pgxpool.Pool) CaptureRecorder {
	return &pgRecorder{pool: pool}
}

// Compile-time interface check.
var _ CaptureRecorder = (*pgRecorder)(nil)

// InsertCapturePosting writes a capture_postings audit row within tx.
// Returns ErrAlreadyPosted on UNIQUE(order_id) conflict (idempotent
// re-delivery of the order.paid event).
func (r *pgRecorder) InsertCapturePosting(ctx context.Context, tx pgx.Tx, p CapturePosting) error {
	const q = `
		INSERT INTO commission_schema.capture_postings
			(order_id, transaction_id, idempotency_key,
			 gross_minor, seller_net_minor, commission_minor, kdv_minor, shipping_minor,
			 currency, market, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'posted')`
	_, err := tx.Exec(ctx, q,
		p.OrderID, p.TransactionID, p.IdempotencyKey,
		p.GrossMinor, p.SellerNetMinor, p.CommissionMinor, p.KdvMinor, p.ShippingMinor,
		p.Currency, p.Market,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return ErrAlreadyPosted
		}
		return err
	}
	return nil
}

// FindCapturePostingByOrderID checks whether an order has already been
// posted. Returns (nil, nil) when no row exists.
//
// Used by orderledger as a fast pre-check before opening an expensive
// SERIALIZABLE transaction; the UNIQUE(order_id) constraint on the table
// is the second independent idempotency guard, so a race here only costs
// an aborted transaction, never a duplicate posting.
func (r *pgRecorder) FindCapturePostingByOrderID(ctx context.Context, orderID int64) (*CapturePosting, error) {
	const q = `
		SELECT id, order_id, transaction_id, idempotency_key,
		       gross_minor, seller_net_minor, commission_minor, kdv_minor, shipping_minor,
		       currency, market, status, created_at
		FROM commission_schema.capture_postings
		WHERE order_id = $1`
	p := &CapturePosting{}
	err := r.pool.QueryRow(ctx, q, orderID).Scan(
		&p.ID, &p.OrderID, &p.TransactionID, &p.IdempotencyKey,
		&p.GrossMinor, &p.SellerNetMinor, &p.CommissionMinor, &p.KdvMinor, &p.ShippingMinor,
		&p.Currency, &p.Market, &p.Status, &p.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return p, nil
}

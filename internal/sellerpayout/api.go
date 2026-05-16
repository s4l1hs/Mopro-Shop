// Package sellerpayout owns the seller net payout engine: scheduling, unlock, and daily cron (fin-svc).
// unlock_at = delivered_at + 3 business days via pkg/timex.AddBusinessDays.
// Net amount = gross - commission - KDV; all amounts frozen at order completion (CLAUDE.md § 4.8).
package sellerpayout

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// OrderDeliveredEvent is the decoded payload from ecom.order.delivered.v1.
// Consumed by SchedulePayoutsForOrder to create per-seller payout rows.
type OrderDeliveredEvent struct {
	OrderID     int64
	DeliveredAt time.Time
	Market      string
	Currency    string
	Items       []DeliveredItem
}

// DeliveredItem holds the per-item commission snapshot from the delivered order event.
type DeliveredItem struct {
	SellerID       int64
	SellerNetMinor int64
}

// Service is the public interface of the seller payout engine (fin-svc only).
type Service interface {
	// SchedulePayoutsForOrder creates one payout row per seller for the delivered order.
	// Payouts are aggregated by seller (one row per seller regardless of item count).
	// Idempotent: returns nil if payouts already exist for this order.
	SchedulePayoutsForOrder(ctx context.Context, ev OrderDeliveredEvent) error
}

// Repository is the storage interface of the seller payout engine (fin-svc only).
type Repository interface {
	InsertPayout(ctx context.Context, tx pgx.Tx, p Payout) (Payout, error)
	FindPayoutByKey(ctx context.Context, idempotencyKey string) (Payout, error)
	WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error
}

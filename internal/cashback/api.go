// Package cashback owns the perpetual cashback engine: plan creation and monthly payments (fin-svc).
// v6 LOCKED PERPETUAL MODEL: monthly_coin = (commission_minor × ref_rate_bps) / 10000 / 12
// Reference interest rate is frozen at 5000 bps (50%) per plan at creation; NEVER changed for existing plans.
package cashback

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// OrderDeliveredEvent is the decoded payload from ecom.order.delivered.v1.
// Consumed by CreatePlanForOrder to create a v6 perpetual cashback plan.
type OrderDeliveredEvent struct {
	OrderID     int64
	UserID      int64
	DeliveredAt time.Time
	Market      string
	Currency    string // fiat currency from the order event; service converts to coin currency
	Items       []CommissionSnapshotItem
}

// Service is the public interface of the cashback engine (fin-svc only).
type Service interface {
	// CreatePlanForOrder creates a v6 perpetual cashback plan for the delivered order.
	// Idempotent: returns nil if a plan already exists for ev.OrderID.
	CreatePlanForOrder(ctx context.Context, ev OrderDeliveredEvent) error
}

// Repository is the storage interface of the cashback engine (fin-svc only).
type Repository interface {
	InsertPlan(ctx context.Context, tx pgx.Tx, p Plan) (Plan, error)
	FindPlanByOrderID(ctx context.Context, orderID int64) (Plan, error)
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
}

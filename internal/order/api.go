// Package order manages order lifecycle, commission snapshot freezing, and delivery events.
// Other modules (payment, seller) import ONLY the Service interface from this package.
package order

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Service is the public interface of the order module.
type Service interface {
	// Checkout is the legacy single-order flow (no PSP call; caller handles payment separately).
	Checkout(ctx context.Context, req CheckoutRequest) (Order, []OrderItem, error)

	// InitiateCheckout is the v8 saga flow: splits cart by seller, persists N orders,
	// calls the PSP, and returns the 3DS HTML fragment for the mobile WebView.
	InitiateCheckout(ctx context.Context, req InitiateCheckoutRequest) (InitiateCheckoutResponse, error)

	GetOrder(ctx context.Context, orderID int64) (Order, []OrderItem, error)
	ListOrders(ctx context.Context, userID int64) ([]Order, error)
	UpdateStatus(ctx context.Context, orderID int64, status OrderStatus) error
	MarkDelivered(ctx context.Context, orderID int64, deliveredAt time.Time) error

	// MarkPaid transitions an order to 'paid' and emits ecom.order.paid.v1.
	// Called by the Sipay webhook handler on capture confirmation. Idempotent.
	MarkPaid(ctx context.Context, orderID int64) error

	// CancelOrder transitions an order to cancelled. Only valid from pending_payment or paid.
	CancelOrder(ctx context.Context, orderID int64, reason string) error
}

// Repository is the storage interface used only by service.go.
type Repository interface {
	InsertOrder(ctx context.Context, tx pgx.Tx, o Order) (Order, error)
	InsertOrderItem(ctx context.Context, tx pgx.Tx, item OrderItem) (OrderItem, error)
	GetOrder(ctx context.Context, orderID int64) (Order, []OrderItem, error)
	GetOrderItems(ctx context.Context, orderID int64) ([]OrderItem, error)
	FindByIdempotencyKey(ctx context.Context, key string) (Order, error)
	ListOrders(ctx context.Context, userID int64) ([]Order, error)
	UpdateStatus(ctx context.Context, tx pgx.Tx, orderID int64, status OrderStatus, updatedAt time.Time) error
	SetDelivered(ctx context.Context, tx pgx.Tx, orderID int64, deliveredAt time.Time) error
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
}

// CheckoutSessionRepository persists checkout session state.
// Kept separate from Repository to avoid breaking existing Repository mocks.
type CheckoutSessionRepository interface {
	InsertCheckoutSession(ctx context.Context, tx pgx.Tx, s CheckoutSession) (CheckoutSession, error)
	FindCheckoutSessionByID(ctx context.Context, id string) (CheckoutSession, error)
	UpdateCheckoutSession(ctx context.Context, id string, status CheckoutSessionStatus, providerRef string) error
}

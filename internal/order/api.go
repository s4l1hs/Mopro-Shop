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

	// ValidateCoupon resolves a coupon code against a basket-discounted subtotal
	// (read-only preview; CT-03/CHK-04). An unknown/invalid code returns a
	// CouponValidation with Valid=false + a Reason — never an error.
	ValidateCoupon(ctx context.Context, code string, subtotalMinor int64, market string) (CouponValidation, error)
}

// Repository is the storage interface used only by service.go.
type Repository interface {
	InsertOrder(ctx context.Context, tx pgx.Tx, o Order) (Order, error)
	InsertOrderItem(ctx context.Context, tx pgx.Tx, item OrderItem) (OrderItem, error)
	GetOrder(ctx context.Context, orderID int64) (Order, []OrderItem, error)
	GetOrderItems(ctx context.Context, orderID int64) ([]OrderItem, error)
	FindByIdempotencyKey(ctx context.Context, key string) (Order, error)

	// InsertOrderAddress persists the frozen delivery-address snapshot for an order
	// (OR-02), encrypting the PII fields at rest. Idempotent: a repeat (order_id) is
	// a no-op. Called inside the checkout persist tx.
	InsertOrderAddress(ctx context.Context, tx pgx.Tx, addr OrderAddress) error

	// GetOrderAddress returns the decrypted delivery-address snapshot for an order, or
	// (nil, nil) when the order has none (legacy orders predating OR-02).
	GetOrderAddress(ctx context.Context, orderID int64) (*OrderAddress, error)
	ListOrders(ctx context.Context, userID int64) ([]Order, error)
	UpdateStatus(ctx context.Context, tx pgx.Tx, orderID int64, status OrderStatus, updatedAt time.Time) error
	SetDelivered(ctx context.Context, tx pgx.Tx, orderID int64, deliveredAt time.Time) error
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error

	// Coupon storage (CT-03/CHK-04). GetCouponByCode returns ErrCouponNotFound when
	// the code is unknown. CountCouponRedemptions backs the max-redemptions guard.
	// InsertCouponRedemption is idempotent (UNIQUE(coupon_id, order_id)) — a repeat
	// (coupon, order) is a no-op, not an error.
	GetCouponByCode(ctx context.Context, code, market string) (Coupon, error)
	CountCouponRedemptions(ctx context.Context, couponID int64) (int, error)
	InsertCouponRedemption(ctx context.Context, tx pgx.Tx, red CouponRedemption) error
}

// CheckoutSessionRepository persists checkout session state.
// Kept separate from Repository to avoid breaking existing Repository mocks.
type CheckoutSessionRepository interface {
	InsertCheckoutSession(ctx context.Context, tx pgx.Tx, s CheckoutSession) (CheckoutSession, error)
	FindCheckoutSessionByID(ctx context.Context, id string) (CheckoutSession, error)
	UpdateCheckoutSession(ctx context.Context, id string, status CheckoutSessionStatus, providerRef string) error
}

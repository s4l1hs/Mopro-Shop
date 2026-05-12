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
	Checkout(ctx context.Context, req CheckoutRequest) (Order, []OrderItem, error)
	GetOrder(ctx context.Context, orderID int64) (Order, []OrderItem, error)
	ListOrders(ctx context.Context, userID int64) ([]Order, error)
	UpdateStatus(ctx context.Context, orderID int64, status OrderStatus) error
	MarkDelivered(ctx context.Context, orderID int64, deliveredAt time.Time) error
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

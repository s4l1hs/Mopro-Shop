// Package cart manages shopping cart state and atomic stock reservation.
// Other modules (order) import ONLY the Service interface from this package.
package cart

import (
	"context"
	"time"
)

// Service is the public interface of the cart module.
// It is the ONLY exported API. Other modules must import this interface, never
// the concrete service or repository types.
type Service interface {
	AddItem(ctx context.Context, userID, variantID int64, qty int) error
	RemoveItem(ctx context.Context, userID, variantID int64) error
	GetCart(ctx context.Context, userID int64) (Cart, error)
	Reserve(ctx context.Context, userID int64) (reservationID string, expiresAt time.Time, err error)
	Release(ctx context.Context, reservationID string) error           // saga compensation; restores stock
	CommitReservation(ctx context.Context, reservationID string) error // order paid; deletes manifest without restoring stock
	SeedStock(ctx context.Context, variantID int64, stock int) error   // test/CLI; TODO(eventbus-wireup)
}

// Repository is the storage interface used only by service.go.
type Repository interface {
	// Cart HASH operations (mopro:cart:user_{id})
	SetItem(ctx context.Context, userID, variantID int64, qty int) error
	RemoveItem(ctx context.Context, userID, variantID int64) error
	GetItems(ctx context.Context, userID int64) ([]CartItem, error)

	// TryReserve atomically checks and decrements stock via Lua EVALSHA.
	// Returns (true, remaining) on success, (false, current) when OUT_OF_STOCK.
	TryReserve(ctx context.Context, variantID int64, qty int, reservationID string, userID int64, ttlSec int64) (ok bool, remaining int, err error)

	// SetManifest stores a HASH of variantID→qty for a reservation (used by ReleaseReservation).
	SetManifest(ctx context.Context, reservationID string, items []CartItem, ttlSec int64) error

	// ReleaseReservation reads the manifest, restores stock, and deletes all reservation keys.
	ReleaseReservation(ctx context.Context, reservationID string) error

	// CommitReservation deletes the manifest and per-item keys without restoring stock.
	// Called after a successful payment: the stock was permanently consumed by the purchase.
	CommitReservation(ctx context.Context, reservationID string) error

	// SeedStock sets the Redis stock counter for a variant (test/CLI use only).
	SeedStock(ctx context.Context, variantID int64, stock int) error
}

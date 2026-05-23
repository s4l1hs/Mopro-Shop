package order

import (
	"context"
	"errors"
)

// ErrDiskPanic is returned by InitiateCheckout when the server is in disk panic mode.
// The handler maps this to HTTP 503 Service Unavailable.
var ErrDiskPanic = errors.New("order: disk pressure panic — service temporarily unavailable")

// DiskPressureChecker reports whether disk panic mode is active.
// Implementations MUST fail-open: if the underlying check fails (e.g. Redis
// unreachable), return false so checkout proceeds normally.
type DiskPressureChecker interface {
	IsDiskPanic(ctx context.Context) bool
}

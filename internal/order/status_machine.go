package order

import "fmt"

// validTransitions defines the allowed FROM → TO state transitions for orders.
// Any transition not listed here is rejected with ErrInvalidTransition.
var validTransitions = map[OrderStatus]map[OrderStatus]bool{
	StatusPendingPayment:    {StatusPaid: true, StatusCancelled: true},
	StatusPaid:              {StatusShipped: true, StatusRefunded: true, StatusCancelled: true},
	StatusShipped:           {StatusDelivered: true},
	StatusDelivered:         {StatusRefunded: true, StatusPartiallyRefunded: true},
	StatusCancelled:         {},
	StatusRefunded:          {},
	StatusPartiallyRefunded: {StatusRefunded: true},
}

// ValidTransition returns nil when transitioning from→to is allowed,
// ErrInvalidTransition otherwise.
func ValidTransition(from, to OrderStatus) error {
	allowed, ok := validTransitions[from]
	if !ok {
		return fmt.Errorf("%w: unknown source status %q", ErrInvalidTransition, from)
	}
	if !allowed[to] {
		return fmt.Errorf("%w: %q → %q is not permitted", ErrInvalidTransition, from, to)
	}
	return nil
}

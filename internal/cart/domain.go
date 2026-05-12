package cart

import "time"

// Cart represents a user's active shopping cart.
type Cart struct {
	UserID int64      `json:"user_id"`
	Items  []CartItem `json:"items"`
}

// CartItem is a single line in the cart.
type CartItem struct {
	VariantID int64 `json:"variant_id"`
	Qty       int   `json:"qty"`
}

// Reservation is a confirmed stock hold built from a cart before checkout.
type Reservation struct {
	ID        string     `json:"id"`
	UserID    int64      `json:"user_id"`
	ExpiresAt time.Time  `json:"expires_at"`
	Items     []CartItem `json:"items"`
}

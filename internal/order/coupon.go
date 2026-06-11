package order

import (
	"strings"
	"time"
)

// Coupon is a cart/order-level discount (CT-03/CHK-04). v1 is seller-funded
// (Salih-confirmed) and percent-only: it applies ON TOP of the per-product basket
// discount (CT-09) via the same per-unit snapshot path, so commission/KDV/
// seller-net/cashback all derive from the coupon-discounted price.
type Coupon struct {
	ID             int64
	Code           string
	Kind           string // "percent" (v1)
	PercentOff     int    // whole percent in [1,100]
	MinBasketMinor int64
	MaxRedemptions *int // nil = unlimited
	StartsAt       time.Time
	ExpiresAt      *time.Time // nil = no expiry
	Active         bool
	Market         string
}

// CouponRedemption records that an order consumed a coupon. Idempotent at the
// storage layer via UNIQUE(coupon_id, order_id) (financial-core §4).
type CouponRedemption struct {
	CouponID      int64
	OrderID       int64
	UserID        int64
	DiscountMinor int64
}

// CouponValidation is the resolved outcome of validating a code against a basket.
// Valid==true means PercentOff is safe to apply and DiscountMinor is the amount the
// coupon takes off the given (already basket-discounted) subtotal. Reason is a
// machine code for the UI when invalid.
type CouponValidation struct {
	Valid         bool
	Code          string
	PercentOff    int
	DiscountMinor int64
	Reason        string // "", "not_found", "inactive", "not_started", "expired", "min_basket", "exhausted"
}

// NormalizeCouponCode trims + uppercases a code for case-insensitive matching.
func NormalizeCouponCode(code string) string {
	return strings.ToUpper(strings.TrimSpace(code))
}

// resolveCoupon validates a coupon against a basket-discounted subtotal at time
// now, given the current redemption count. It is pure (no IO) so it is identically
// reusable by the cart-display path and the order-build (charge) path — which is
// what guarantees display==charge. A nil coupon yields an invalid result.
func resolveCoupon(c *Coupon, subtotalMinor int64, redemptions int, now time.Time) CouponValidation {
	if c == nil {
		return CouponValidation{Reason: "not_found"}
	}
	out := CouponValidation{Code: c.Code, PercentOff: c.PercentOff}
	switch {
	case !c.Active:
		out.Reason = "inactive"
	case now.Before(c.StartsAt):
		out.Reason = "not_started"
	case c.ExpiresAt != nil && !now.Before(*c.ExpiresAt):
		out.Reason = "expired"
	case subtotalMinor < c.MinBasketMinor:
		out.Reason = "min_basket"
	case c.MaxRedemptions != nil && redemptions >= *c.MaxRedemptions:
		out.Reason = "exhausted"
	default:
		out.Valid = true
		// Discount preview on the whole basket; the actual charge applies the same
		// percent per unit (BasketDiscountMinor), which sums to this for a flat pct.
		out.DiscountMinor = BasketDiscountMinor(subtotalMinor, c.PercentOff)
	}
	return out
}

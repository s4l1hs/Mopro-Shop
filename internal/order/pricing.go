package order

// Basket-discount pricing helpers (CT-09). Pure integer math, no float
// (CLAUDE.md §4.6). These are the SINGLE source of truth for the seller-funded
// "Sepette %X İndirim": both the cart display (cmd/core-svc/enrichCart) and the
// order build (Checkout / InitiateCheckout) call them, so the price the buyer
// sees can never diverge from the price the buyer is charged (the asymmetry rule).
//
// Coupon (CT-03/CHK-04) reuses BasketDiscountMinor for its own percentage line;
// the order carries a single discount_minor aggregate either source feeds.

// BasketDiscountMinor returns the discount amount in minor units for a
// whole-percent discount on baseMinor, using round-half-up (consumer-friendly:
// ties round in the buyer's favour). Deterministic; pct is clamped to [0,100];
// a non-positive pct or base yields 0.
func BasketDiscountMinor(baseMinor int64, pct int) int64 {
	if pct <= 0 || baseMinor <= 0 {
		return 0
	}
	if pct > 100 {
		pct = 100
	}
	// round-half-up: (base*pct + 50) / 100. base*pct stays well within int64 for
	// any realistic price (base ≤ 1e14 kuruş, pct ≤ 100 → ≤ 1e16 ≪ 9.2e18).
	return (baseMinor*int64(pct) + 50) / 100
}

// DiscountedUnitMinor applies BasketDiscountMinor to a unit price and returns the
// effective (charged) unit price. The discount is applied per unit so the
// snapshot unit_price_minor is itself the charged unit (line = result × qty).
// Never negative.
func DiscountedUnitMinor(unitPriceMinor int64, pct int) int64 {
	return unitPriceMinor - BasketDiscountMinor(unitPriceMinor, pct)
}

// basketPctOf normalizes an optional product basket_discount_pct pointer to a
// clamped whole percent in [0,100]; nil or out-of-range collapses to 0.
func basketPctOf(pct *int) int {
	if pct == nil || *pct <= 0 {
		return 0
	}
	if *pct > 100 {
		return 100
	}
	return *pct
}

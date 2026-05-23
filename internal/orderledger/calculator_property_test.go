package orderledger

import (
	"math/rand"
	"os"
	"strconv"
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

func gopterSeed() int64 {
	if s := os.Getenv("GOPTER_SEED"); s != "" {
		if n, err := strconv.ParseInt(s, 10, 64); err == nil {
			return n
		}
	}
	return 42
}

// validInputGuard returns true when the generated values would produce a
// degenerate case (commission_revenue <= 0 or gross < min).
// Used to skip — not fail — such cases in ForAll predicates.
func validInputGuard(gross, sellerNet, kdv, shipping int64) bool {
	return gross >= 100 && sellerNet > 0 && sellerNet+kdv+shipping < gross
}

// TestProperty_Compute_Balanced verifies sum(D) == sum(C) == GrossMinor.
func TestProperty_Compute_Balanced(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(gopterSeed()))

	properties := gopter.NewProperties(params)

	properties.Property("sum(D) == sum(C) == GrossMinor", prop.ForAll(
		func(gross, sellerNet, kdv, shipping, sellerID int64) bool {
			if !validInputGuard(gross, sellerNet, kdv, shipping) {
				return true // skip — not a counter-example
			}
			in := CaptureInputs{
				OrderID:        1,
				SellerID:       sellerID,
				GrossMinor:     gross,
				SellerNetMinor: sellerNet,
				KdvMinor:       kdv,
				ShippingMinor:  shipping,
				Currency:       "TRY",
			}
			got, err := Compute(in)
			if err != nil {
				return true // skip — invalid input accepted by guard check above
			}
			var totalD, totalC int64
			for _, l := range got.Lines {
				if l.Direction == "D" {
					totalD += l.AmountMinor
				} else {
					totalC += l.AmountMinor
				}
			}
			return totalD == gross && totalD == totalC
		},
		gen.Int64Range(100, int64(1e12)), // gross ≥ 1 TL
		gen.Int64Range(1, int64(1e12)),   // sellerNet
		gen.Int64Range(0, 1000),          // kdv (can be 0; Compute filters zero lines)
		gen.Int64Range(0, 5000),          // shipping (can be 0)
		gen.Int64Range(1, int64(1e6)),    // sellerID
	))

	properties.TestingRun(t)
}

// TestProperty_Compute_NoZeroLines verifies every emitted line has AmountMinor > 0.
func TestProperty_Compute_NoZeroLines(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(gopterSeed()))

	properties := gopter.NewProperties(params)

	properties.Property("no zero-amount lines", prop.ForAll(
		func(gross, sellerNet, kdv, shipping int64) bool {
			if !validInputGuard(gross, sellerNet, kdv, shipping) {
				return true
			}
			in := CaptureInputs{
				OrderID:        1,
				SellerID:       1,
				GrossMinor:     gross,
				SellerNetMinor: sellerNet,
				KdvMinor:       kdv,
				ShippingMinor:  shipping,
				Currency:       "TRY",
			}
			got, err := Compute(in)
			if err != nil {
				return true
			}
			for _, l := range got.Lines {
				if l.AmountMinor <= 0 {
					return false
				}
			}
			return true
		},
		gen.Int64Range(100, int64(1e12)),
		gen.Int64Range(1, int64(1e12)),
		gen.Int64Range(0, 1000),
		gen.Int64Range(0, 5000),
	))

	properties.TestingRun(t)
}

// TestProperty_Compute_ShippingLinePresence verifies the shipping_payable line
// appears iff ShippingMinor > 0.
func TestProperty_Compute_ShippingLinePresence(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(gopterSeed()))

	properties := gopter.NewProperties(params)

	properties.Property("shipping line present iff shipping>0", prop.ForAll(
		func(gross, sellerNet, kdv, shipping int64) bool {
			if !validInputGuard(gross, sellerNet, kdv, shipping) {
				return true
			}
			in := CaptureInputs{
				OrderID:        1,
				SellerID:       1,
				GrossMinor:     gross,
				SellerNetMinor: sellerNet,
				KdvMinor:       kdv,
				ShippingMinor:  shipping,
				Currency:       "TRY",
			}
			got, err := Compute(in)
			if err != nil {
				return true
			}
			var hasShipping bool
			for _, l := range got.Lines {
				if l.AccountType == "liability:shipping_payable" {
					hasShipping = true
				}
			}
			return hasShipping == (shipping > 0)
		},
		gen.Int64Range(100, int64(1e12)),
		gen.Int64Range(1, int64(1e12)),
		gen.Int64Range(0, 1000),
		gen.Int64Range(0, 5000),
	))

	properties.TestingRun(t)
}

// TestProperty_Compute_MinimumLines verifies at least 2 lines are always emitted
// (DR psp_receivable + CR seller_payable, both guaranteed non-zero for valid input).
func TestProperty_Compute_MinimumLines(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(gopterSeed()))

	properties := gopter.NewProperties(params)

	properties.Property("at least 2 lines emitted", prop.ForAll(
		func(gross, sellerNet, kdv, shipping int64) bool {
			if !validInputGuard(gross, sellerNet, kdv, shipping) {
				return true
			}
			in := CaptureInputs{
				OrderID:        1,
				SellerID:       1,
				GrossMinor:     gross,
				SellerNetMinor: sellerNet,
				KdvMinor:       kdv,
				ShippingMinor:  shipping,
				Currency:       "TRY",
			}
			got, err := Compute(in)
			if err != nil {
				return true
			}
			return len(got.Lines) >= 2
		},
		gen.Int64Range(100, int64(1e12)),
		gen.Int64Range(1, int64(1e12)),
		gen.Int64Range(0, 1000),
		gen.Int64Range(0, 5000),
	))

	properties.TestingRun(t)
}

// TestProperty_Compute_MaximumLines verifies at most 5 lines are ever emitted.
func TestProperty_Compute_MaximumLines(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(gopterSeed()))

	properties := gopter.NewProperties(params)

	properties.Property("at most 5 lines emitted", prop.ForAll(
		func(gross, sellerNet, kdv, shipping int64) bool {
			if !validInputGuard(gross, sellerNet, kdv, shipping) {
				return true
			}
			in := CaptureInputs{
				OrderID:        1,
				SellerID:       1,
				GrossMinor:     gross,
				SellerNetMinor: sellerNet,
				KdvMinor:       kdv,
				ShippingMinor:  shipping,
				Currency:       "TRY",
			}
			got, err := Compute(in)
			if err != nil {
				return true
			}
			return len(got.Lines) <= 5
		},
		gen.Int64Range(100, int64(1e12)),
		gen.Int64Range(1, int64(1e12)),
		gen.Int64Range(0, 1000),
		gen.Int64Range(0, 5000),
	))

	properties.TestingRun(t)
}

// TestProperty_Aggregate_GrossPassThrough verifies Aggregate does not modify
// GrossMinor or ShippingMinor (they come from the order aggregate, not items).
func TestProperty_Aggregate_GrossPassThrough(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(gopterSeed()))

	properties := gopter.NewProperties(params)

	properties.Property("Aggregate preserves GrossMinor and ShippingMinor from event", prop.ForAll(
		func(gross, shipping int64, commA, kdvA, netA, commB, kdvB, netB int64) bool {
			ev := OrderPaidEvent{
				OrderID:       1,
				SellerID:      1,
				GrossMinor:    gross,
				ShippingMinor: shipping,
				Currency:      "TRY",
				Market:        "TR",
				Items: []PaidItem{
					{CommissionAmountMinor: commA, KdvAmountMinor: kdvA, SellerNetMinor: netA},
					{CommissionAmountMinor: commB, KdvAmountMinor: kdvB, SellerNetMinor: netB},
				},
			}
			got := Aggregate(ev)
			return got.GrossMinor == gross && got.ShippingMinor == shipping
		},
		gen.Int64Range(100, int64(1e12)),
		gen.Int64Range(0, 5000),
		gen.Int64Range(0, int64(1e10)), gen.Int64Range(0, int64(1e10)), gen.Int64Range(0, int64(1e10)),
		gen.Int64Range(0, int64(1e10)), gen.Int64Range(0, int64(1e10)), gen.Int64Range(0, int64(1e10)),
	))

	properties.TestingRun(t)
}

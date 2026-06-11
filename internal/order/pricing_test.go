package order

import (
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

func TestBasketDiscountMinor_Examples(t *testing.T) {
	tests := []struct {
		name string
		base int64
		pct  int
		want int64
	}{
		{"zero pct", 8000, 0, 0},
		{"negative pct", 8000, -5, 0},
		{"zero base", 0, 15, 0},
		{"15pct of 80.00", 8000, 15, 1200}, // 8000*15/100 = 1200
		{"10pct of 99.90", 9990, 10, 999},  // 9990*10/100 = 999
		{"round half up", 333, 15, 50},     // 333*15=4995, +50=5045, /100 = 50 (49.95→50)
		{"clamp >100", 8000, 250, 8000},    // clamped to 100% → full base
		{"100pct", 8000, 100, 8000},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := BasketDiscountMinor(tc.base, tc.pct); got != tc.want {
				t.Errorf("BasketDiscountMinor(%d,%d) = %d, want %d", tc.base, tc.pct, got, tc.want)
			}
		})
	}
}

func TestDiscountedUnitMinor_NeverExceedsList(t *testing.T) {
	if got := DiscountedUnitMinor(8000, 15); got != 6800 {
		t.Errorf("DiscountedUnitMinor(8000,15) = %d, want 6800", got)
	}
	if got := DiscountedUnitMinor(8000, 0); got != 8000 {
		t.Errorf("DiscountedUnitMinor(8000,0) = %d, want 8000 (no discount)", got)
	}
}

func intPtr(i int) *int { return &i }

func TestBasketPctOf(t *testing.T) {
	cases := []struct {
		in   *int
		want int
	}{
		{nil, 0}, {intPtr(0), 0}, {intPtr(-3), 0}, {intPtr(15), 15}, {intPtr(150), 100},
	}
	for _, c := range cases {
		if got := basketPctOf(c.in); got != c.want {
			t.Errorf("basketPctOf(%v) = %d, want %d", c.in, got, c.want)
		}
	}
}

// Property: the discount is always in [0, base], the discounted unit is in
// [0, base], and the post-discount commission snapshot keeps seller_net >= 0 and
// commission+kdv <= gross (CLAUDE.md §4.8 invariant on the DISCOUNTED gross).
func TestProperty_BasketDiscountInvariants(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 2000
	properties := gopter.NewProperties(params)

	properties.Property("discount bounded and snapshot stays valid on discounted gross", prop.ForAll(
		func(unit int64, qty uint8, pct uint8, commBps uint16, kdvBps uint16) bool {
			if unit <= 0 || qty == 0 {
				return true
			}
			p := int(pct % 101) // [0,100]
			disc := BasketDiscountMinor(unit, p)
			if disc < 0 || disc > unit {
				return false
			}
			discUnit := DiscountedUnitMinor(unit, p)
			if discUnit < 0 || discUnit > unit {
				return false
			}
			// Order-build math on the discounted gross.
			cb := int(commBps % 3001) // ≤30%
			kb := int(kdvBps % 4001)  // ≤40%
			gross := discUnit * int64(qty)
			comm := gross * int64(cb) / 10000
			kdv := comm * int64(kb) / 10000
			net := gross - comm - kdv
			return net >= 0 && comm >= 0 && kdv >= 0 && comm+kdv <= gross
		},
		gen.Int64Range(1, 100_000_000),
		gen.UInt8Range(1, 50),
		gen.UInt8Range(0, 100),
		gen.UInt16Range(0, 3000),
		gen.UInt16Range(0, 4000),
	))

	properties.TestingRun(t)
}

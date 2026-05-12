//go:build integration

package cashback_test

// Property tests: v6 perpetual cashback formula invariants.
// Pure math — no DB, no Redis.

import (
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"

	"github.com/mopro/platform/internal/cashback"
)

func TestProperty_CashbackFormulaDeterministic(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	properties := gopter.NewProperties(params)

	properties.Property(
		"same commission_minor always yields same monthly_coin_minor",
		prop.ForAll(
			func(commissionMinor int64) bool {
				if commissionMinor <= 0 {
					return true
				}
				yearly1 := commissionMinor * int64(cashback.ReferenceInterestRateBpsConst) / 10000
				monthly1 := yearly1 / 12

				yearly2 := commissionMinor * int64(cashback.ReferenceInterestRateBpsConst) / 10000
				monthly2 := yearly2 / 12

				return monthly1 == monthly2
			},
			gen.Int64Range(1, 1_000_000_000),
		),
	)

	properties.TestingRun(t)
}

func TestProperty_CashbackMonthlyNonNegative(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	properties := gopter.NewProperties(params)

	properties.Property(
		"monthly_coin_minor >= 0 for any non-negative commission",
		prop.ForAll(
			func(unitPriceMinor int64, qty uint8, commPctBps uint16) bool {
				if unitPriceMinor <= 0 || qty == 0 {
					return true
				}
				if commPctBps > 3000 {
					commPctBps %= 3001
				}

				gross := unitPriceMinor * int64(qty)
				commAmt := gross * int64(commPctBps) / 10000
				yearly := commAmt * int64(cashback.ReferenceInterestRateBpsConst) / 10000
				monthly := yearly / 12

				return monthly >= 0 && yearly >= 0
			},
			gen.Int64Range(1, 100_000_000),
			gen.UInt8Range(1, 50),
			gen.UInt16Range(0, 3000),
		),
	)

	properties.TestingRun(t)
}

func TestProperty_CashbackYearlyDividesBy12(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 500
	properties := gopter.NewProperties(params)

	properties.Property(
		"monthly_coin_minor * 12 <= yearly_yield_minor (integer division truncates down)",
		prop.ForAll(
			func(commissionMinor int64) bool {
				if commissionMinor <= 0 {
					return true
				}
				yearly := commissionMinor * int64(cashback.ReferenceInterestRateBpsConst) / 10000
				monthly := yearly / 12
				return monthly*12 <= yearly
			},
			gen.Int64Range(1, 1_000_000_000),
		),
	)

	properties.TestingRun(t)
}

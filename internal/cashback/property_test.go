//go:build integration

package cashback_test

// Property tests: v8 accelerated amortization formula invariants.
// Pure math — no DB, no Redis.

import (
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"

	"github.com/mopro/platform/internal/cashback"
)

// TestProperty_V8Formula_PrincipalCoverage verifies that the sum of all installments
// equals priceMinor exactly for any valid input combination.
func TestProperty_V8Formula_PrincipalCoverage(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	properties := gopter.NewProperties(params)

	properties.Property(
		"(T-1)*M + M_last == priceMinor (principal exactly covered)",
		prop.ForAll(
			func(priceMinor int64, commissionBps int) bool {
				terms, err := cashback.ComputePlanTerms(priceMinor, commissionBps)
				if err != nil {
					return true // invalid input — skip
				}
				sum := int64(terms.TotalMonths-1)*terms.MonthlyAmountMinor + terms.MonthlyAmountLastMinor
				return sum == priceMinor
			},
			gen.Int64Range(1, int64(1e14)),
			gen.IntRange(100, 10000),
		),
	)

	properties.TestingRun(t)
}

// TestProperty_V8Formula_MonthlyNonNegative verifies that all output fields
// are positive when ComputePlanTerms succeeds.
func TestProperty_V8Formula_MonthlyNonNegative(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	properties := gopter.NewProperties(params)

	properties.Property(
		"MonthlyAmountMinor >= 1 and MonthlyAmountLastMinor >= MonthlyAmountMinor",
		prop.ForAll(
			func(priceMinor int64, commissionBps int) bool {
				terms, err := cashback.ComputePlanTerms(priceMinor, commissionBps)
				if err != nil {
					return true
				}
				return terms.MonthlyAmountMinor >= 1 &&
					terms.MonthlyAmountLastMinor >= terms.MonthlyAmountMinor
			},
			gen.Int64Range(1, int64(1e14)),
			gen.IntRange(100, 10000),
		),
	)

	properties.TestingRun(t)
}

// TestProperty_V8Formula_TotalMonthsDeterministic verifies that
// ComputePlanTerms returns the same result when called twice with the same inputs.
func TestProperty_V8Formula_TotalMonthsDeterministic(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 500
	properties := gopter.NewProperties(params)

	properties.Property(
		"same inputs always yield identical PlanTerms",
		prop.ForAll(
			func(priceMinor int64, commissionBps int) bool {
				t1, err1 := cashback.ComputePlanTerms(priceMinor, commissionBps)
				t2, err2 := cashback.ComputePlanTerms(priceMinor, commissionBps)
				if (err1 == nil) != (err2 == nil) {
					return false
				}
				if err1 != nil {
					return true
				}
				return t1.TotalMonths == t2.TotalMonths &&
					t1.MonthlyAmountMinor == t2.MonthlyAmountMinor &&
					t1.MonthlyAmountLastMinor == t2.MonthlyAmountLastMinor
			},
			gen.Int64Range(1, int64(1e14)),
			gen.IntRange(100, 10000),
		),
	)

	properties.TestingRun(t)
}

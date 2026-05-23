package cashback

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

// TestProperty_ComputePlanTerms_PrincipalCoverage verifies that for all valid
// inputs the sum of all installments equals priceMinor exactly (no rounding leak).
func TestProperty_ComputePlanTerms_PrincipalCoverage(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(gopterSeed()))

	properties := gopter.NewProperties(params)

	properties.Property("(T-1)*M + M_last == priceMinor", prop.ForAll(
		func(priceMinor int64, commissionBps int) bool {
			terms, err := ComputePlanTerms(priceMinor, commissionBps)
			if err != nil {
				return true // invalid input — not a counter-example
			}
			sum := int64(terms.TotalMonths-1)*terms.MonthlyAmountMinor + terms.MonthlyAmountLastMinor
			return sum == priceMinor
		},
		gen.Int64Range(1, int64(1e14)),
		gen.IntRange(100, 10000),
	))

	properties.Property("sum of InstallmentAmount(1..T) == priceMinor", prop.ForAll(
		func(priceMinor int64, commissionBps int) bool {
			terms, err := ComputePlanTerms(priceMinor, commissionBps)
			if err != nil {
				return true
			}
			var total int64
			for i := 1; i <= terms.TotalMonths; i++ {
				total += InstallmentAmount(terms, i)
			}
			return total == priceMinor
		},
		gen.Int64Range(1, int64(1e14)),
		gen.IntRange(100, 10000),
	))

	properties.TestingRun(t)
}

// TestProperty_ComputePlanTerms_MonotonicInvariants checks structural invariants
// on the returned PlanTerms: TotalMonths >= 1, MonthlyAmountMinor >= 1,
// MonthlyAmountLastMinor >= MonthlyAmountMinor.
func TestProperty_ComputePlanTerms_MonotonicInvariants(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(gopterSeed()))

	properties := gopter.NewProperties(params)

	properties.Property("TotalMonths >= 1", prop.ForAll(
		func(priceMinor int64, commissionBps int) bool {
			terms, err := ComputePlanTerms(priceMinor, commissionBps)
			if err != nil {
				return true
			}
			return terms.TotalMonths >= 1
		},
		gen.Int64Range(1, int64(1e14)),
		gen.IntRange(100, 10000),
	))

	properties.Property("MonthlyAmountMinor >= 1", prop.ForAll(
		func(priceMinor int64, commissionBps int) bool {
			terms, err := ComputePlanTerms(priceMinor, commissionBps)
			if err != nil {
				return true
			}
			return terms.MonthlyAmountMinor >= 1
		},
		gen.Int64Range(1, int64(1e14)),
		gen.IntRange(100, 10000),
	))

	properties.Property("MonthlyAmountLastMinor >= MonthlyAmountMinor", prop.ForAll(
		func(priceMinor int64, commissionBps int) bool {
			terms, err := ComputePlanTerms(priceMinor, commissionBps)
			if err != nil {
				return true
			}
			return terms.MonthlyAmountLastMinor >= terms.MonthlyAmountMinor
		},
		gen.Int64Range(1, int64(1e14)),
		gen.IntRange(100, 10000),
	))

	properties.TestingRun(t)
}

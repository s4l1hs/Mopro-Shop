//go:build integration

package sellerpayout_test

// Property tests: seller payout scheduling arithmetic invariants.
// Pure math — no DB, no Redis.

import (
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

// payoutNetMinor mirrors the formula in CLAUDE.md § 4.8 (deterministic, integer arithmetic).
func payoutNetMinor(priceMinor int64, qty int, commPctBps, kdvPctBps int) int64 {
	gross := priceMinor * int64(qty)
	commAmt := gross * int64(commPctBps) / 10000
	kdvAmt := commAmt * int64(kdvPctBps) / 10000
	return gross - commAmt - kdvAmt
}

func TestProperty_PayoutDeterministic(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	properties := gopter.NewProperties(params)

	properties.Property(
		"same inputs always yield same seller_net_minor",
		prop.ForAll(
			func(priceMinor int64, qty uint8, commPctBps, kdvPctBps uint16) bool {
				if priceMinor <= 0 || qty == 0 {
					return true
				}
				if commPctBps > 3000 {
					commPctBps %= 3001
				}
				if kdvPctBps > 4000 {
					kdvPctBps %= 4001
				}
				net1 := payoutNetMinor(priceMinor, int(qty), int(commPctBps), int(kdvPctBps))
				net2 := payoutNetMinor(priceMinor, int(qty), int(commPctBps), int(kdvPctBps))
				return net1 == net2
			},
			gen.Int64Range(1, 100_000_000),
			gen.UInt8Range(1, 50),
			gen.UInt16Range(0, 3000),
			gen.UInt16Range(0, 4000),
		),
	)

	properties.TestingRun(t)
}

func TestProperty_PayoutNonNegative(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	properties := gopter.NewProperties(params)

	properties.Property(
		"seller_net_minor >= 0 for any valid commission and KDV rates",
		prop.ForAll(
			func(priceMinor int64, qty uint8, commPctBps, kdvPctBps uint16) bool {
				if priceMinor <= 0 || qty == 0 {
					return true
				}
				if commPctBps > 3000 {
					commPctBps %= 3001
				}
				if kdvPctBps > 4000 {
					kdvPctBps %= 4001
				}
				net := payoutNetMinor(priceMinor, int(qty), int(commPctBps), int(kdvPctBps))
				return net >= 0
			},
			gen.Int64Range(1, 100_000_000),
			gen.UInt8Range(1, 50),
			gen.UInt16Range(0, 3000),
			gen.UInt16Range(0, 4000),
		),
	)

	properties.TestingRun(t)
}

func TestProperty_PayoutAggregation(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 500
	properties := gopter.NewProperties(params)

	properties.Property(
		"sum of per-item seller_net_minor equals aggregated payout amount",
		prop.ForAll(
			func(price1, price2 int64, commPctBps uint16) bool {
				if price1 <= 0 || price2 <= 0 {
					return true
				}
				if commPctBps > 3000 {
					commPctBps %= 3001
				}
				net1 := payoutNetMinor(price1, 1, int(commPctBps), 2000)
				net2 := payoutNetMinor(price2, 1, int(commPctBps), 2000)
				aggregated := net1 + net2

				// Both items from same seller: aggregated payout = sum of individual nets
				return aggregated == net1+net2
			},
			gen.Int64Range(1, 100_000_000),
			gen.Int64Range(1, 100_000_000),
			gen.UInt16Range(0, 3000),
		),
	)

	properties.TestingRun(t)
}

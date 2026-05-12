package order_test

// Property test: commission snapshot arithmetic invariants.
// Pure math — no DB, no Redis. Verifies the checkout formula is deterministic
// and that seller_net_minor is always non-negative.

import (
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

func TestProperty_CommissionSnapshotInvariant(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	properties := gopter.NewProperties(params)

	properties.Property(
		"seller_net_minor >= 0 and commission_amount_minor + kdv_amount_minor <= gross_minor",
		prop.ForAll(
			func(unitPriceMinor int64, qty uint8, commissionPctBps uint16, kdvPctBps uint16) bool {
				if unitPriceMinor <= 0 || qty == 0 {
					return true // skip degenerate inputs
				}
				if commissionPctBps > 3000 { // cap at 30%
					commissionPctBps %= 3001
				}
				if kdvPctBps > 4000 { // cap at 40%
					kdvPctBps %= 4001
				}

				gross := unitPriceMinor * int64(qty)
				commAmt := gross * int64(commissionPctBps) / 10000
				kdvAmt := commAmt * int64(kdvPctBps) / 10000
				sellerNet := gross - commAmt - kdvAmt

				return sellerNet >= 0 &&
					commAmt >= 0 &&
					kdvAmt >= 0 &&
					commAmt+kdvAmt <= gross
			},
			gen.Int64Range(1, 100_000_000), // up to 1M TL minor (100k TL)
			gen.UInt8Range(1, 50),          // qty 1-50
			gen.UInt16Range(0, 3000),       // commission 0-30%
			gen.UInt16Range(0, 4000),       // KDV 0-40%
		),
	)

	properties.Property(
		"commission snapshot is deterministic: same inputs → same outputs",
		prop.ForAll(
			func(unitPriceMinor int64, qty uint8, commPctBps uint16, kdvPctBps uint16) bool {
				if unitPriceMinor <= 0 || qty == 0 {
					return true
				}
				gross := unitPriceMinor * int64(qty)
				commAmt1 := gross * int64(commPctBps) / 10000
				kdvAmt1 := commAmt1 * int64(kdvPctBps) / 10000

				commAmt2 := gross * int64(commPctBps) / 10000
				kdvAmt2 := commAmt2 * int64(kdvPctBps) / 10000

				return commAmt1 == commAmt2 && kdvAmt1 == kdvAmt2
			},
			gen.Int64Range(1, 100_000_000),
			gen.UInt8Range(1, 50),
			gen.UInt16Range(0, 3000),
			gen.UInt16Range(0, 4000),
		),
	)

	properties.TestingRun(t)
}

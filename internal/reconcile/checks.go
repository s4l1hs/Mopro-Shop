package reconcile

import (
	"context"
	"fmt"
	"time"
)

// runCheck1DCInvariant verifies Sum(D) == Sum(C) across all ledger_entries per currency.
// Any non-zero delta means a ledger invariant violation — always CRITICAL.
func runCheck1DCInvariant(ctx context.Context, repo Repository) ([]CheckResult, error) {
	deltas, err := repo.Check1DCBalance(ctx)
	if err != nil {
		return nil, fmt.Errorf("check1: %w", err)
	}

	var results []CheckResult
	for currency, delta := range deltas {
		results = append(results, CheckResult{
			CheckName:  "check1_dc_invariant",
			Passed:     false,
			DriftMinor: delta,
			Details:    fmt.Sprintf("currency=%s delta=%d (non-zero D-C sum)", currency, delta),
		})
	}
	// If deltas is empty, all currencies balanced — return empty slice (no failures).
	return results, nil
}

// buildCheck1DedupKey returns the PagerDuty dedup key for a check1 failure.
func buildCheck1DedupKey(currency string) string {
	return fmt.Sprintf("reconcile:check1_dc_invariant:%s", currency)
}

// runCheck2CashbackBackward verifies that the sum of paid cashback payments matches
// the sum of ledger C entries linked via ledger_transaction_id, for the last 3 periods.
func runCheck2CashbackBackward(ctx context.Context, repo Repository, asOfPeriod int) ([]CheckResult, error) {
	periods := []int{
		asOfPeriod,
		prevPeriod(asOfPeriod),
		prevPeriod(prevPeriod(asOfPeriod)),
	}

	var results []CheckResult
	for _, period := range periods {
		paymentsTotal, ledgerTotal, err := repo.Check2CashbackBackward(ctx, period)
		if err != nil {
			return nil, fmt.Errorf("check2 period=%d: %w", period, err)
		}
		if paymentsTotal == ledgerTotal {
			continue // pass
		}
		drift := paymentsTotal - ledgerTotal
		if drift < 0 {
			drift = -drift
		}
		results = append(results, CheckResult{
			CheckName:  "check2_cashback_backward",
			Passed:     false,
			DriftMinor: drift,
			Details:    fmt.Sprintf("period=%d payments_total=%d ledger_total=%d drift=%d", period, paymentsTotal, ledgerTotal, drift),
		})
	}
	return results, nil
}

// buildCheck2DedupKey returns the PagerDuty dedup key for a check2 failure.
func buildCheck2DedupKey(periodYYYYMM int, currency string) string {
	return fmt.Sprintf("reconcile:check2_cashback_backward:%d:%s", periodYYYYMM, currency)
}

// prevPeriod returns the YYYYMM of the month before p.
func prevPeriod(p int) int {
	year, month := p/100, p%100
	month--
	if month == 0 {
		month = 12
		year--
	}
	return year*100 + month
}

// periodFromTime converts time.Time to YYYYMM integer.
func periodFromTime(t time.Time) int {
	return t.Year()*100 + int(t.Month())
}

// buildDedupKey builds a generic dedup key from check name and details string.
func buildDedupKey(checkName, details string) string {
	return fmt.Sprintf("reconcile:%s:%s", checkName, details)
}

// ensure buildCheck1DedupKey and buildCheck2DedupKey are referenced to avoid unused warnings.
var _ = buildCheck1DedupKey
var _ = buildCheck2DedupKey

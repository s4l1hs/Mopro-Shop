package reconcile

import "time"

// CheckResult is the outcome of one invariant check.
type CheckResult struct {
	CheckName  string
	Passed     bool
	DriftMinor int64  // 0 when Passed=true
	Details    string // human-readable context
}

// ReconcileAlert is an alert row to be written to wallet_schema.ledger_alerts.
type ReconcileAlert struct {
	CheckName        string
	CurrencyOrPeriod string // currency for check1, "YYYYMM:CCY" for check2
	Expected         int64
	Observed         int64
	DriftMinor       int64
	DedupKey         string
}

// WeeklyResult summarises one RunWeekly execution.
type WeeklyResult struct {
	AsOf           time.Time
	AlertsInserted int
	Errors         []error
}

package metrics_test

import (
	"testing"

	"github.com/mopro/platform/pkg/metrics"
)

func TestBusinessMetrics_NilSafe(t *testing.T) {
	var m *metrics.BusinessMetrics
	// All methods must be safe to call on nil receiver — no panic.
	m.IncOrderStatusTransition("svc", "pending", "paid")
	m.IncCashbackPlanCreated("svc", "TR")
	m.IncCashbackInstallmentPaid("svc", "TR")
	m.IncOrderLedgerPosting("svc", "TR")
	m.IncOTPRequest("svc", "login")
	m.IncOTPVerifyOutcome("svc", "success")
}

func TestBusinessMetrics_IncrementsAllCounters(t *testing.T) {
	reg := metrics.New("test-svc")
	m := metrics.NewBusinessMetrics(reg)

	m.IncOrderStatusTransition("test-svc", "pending_payment", "paid")
	m.IncOrderStatusTransition("test-svc", "paid", "shipped")
	m.IncCashbackPlanCreated("test-svc", "TR")
	m.IncCashbackInstallmentPaid("test-svc", "TR")
	m.IncOrderLedgerPosting("test-svc", "TR")
	m.IncOTPRequest("test-svc", "login")
	m.IncOTPRequest("test-svc", "stepup")
	m.IncOTPVerifyOutcome("test-svc", "success")
	m.IncOTPVerifyOutcome("test-svc", "invalid")

	mfs, err := reg.Prometheus().Gather()
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}

	cases := []struct {
		metric string
		minVal float64
	}{
		{"mopro_order_status_transitions_total", 2},
		{"mopro_cashback_plans_created_total", 1},
		{"mopro_cashback_installments_paid_total", 1},
		{"mopro_orderledger_postings_total", 1},
		{"mopro_otp_requests_total", 2},
		{"mopro_otp_verify_outcomes_total", 2},
	}

	totals := make(map[string]float64)
	for _, mf := range mfs {
		for _, metric := range mf.GetMetric() {
			if c := metric.GetCounter(); c != nil {
				totals[mf.GetName()] += c.GetValue()
			}
		}
	}

	for _, tc := range cases {
		if totals[tc.metric] < tc.minVal {
			t.Errorf("%s: expected sum >= %v, got %v", tc.metric, tc.minVal, totals[tc.metric])
		}
	}
}

func TestBusinessMetrics_LabelCombinationsValid(t *testing.T) {
	reg := metrics.New("test-svc")
	m := metrics.NewBusinessMetrics(reg)

	// Verify that after incrementing with different label values,
	// all expected label combinations appear in the gathered output.
	m.IncOrderStatusTransition("test-svc", "pending_payment", "paid")
	m.IncOrderStatusTransition("test-svc", "paid", "delivered")
	m.IncOTPVerifyOutcome("test-svc", "success")
	m.IncOTPVerifyOutcome("test-svc", "expired")
	m.IncOTPVerifyOutcome("test-svc", "rate_limited")

	mfs, _ := reg.Prometheus().Gather()
	byName := make(map[string]*struct{ series int })
	for _, mf := range mfs {
		byName[mf.GetName()] = &struct{ series int }{series: len(mf.GetMetric())}
	}

	if s := byName["mopro_order_status_transitions_total"]; s == nil || s.series < 2 {
		t.Errorf("expected ≥2 series for transitions, got %v", byName["mopro_order_status_transitions_total"])
	}
	if s := byName["mopro_otp_verify_outcomes_total"]; s == nil || s.series < 3 {
		t.Errorf("expected ≥3 series for otp verify outcomes, got %v", byName["mopro_otp_verify_outcomes_total"])
	}
}

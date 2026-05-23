package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
)

// BusinessMetrics holds all domain-level KPI counters. Pass *BusinessMetrics
// to service constructors. All methods are nil-safe — callers do not need to
// nil-check before calling.
type BusinessMetrics struct {
	orderStatusTransitions   *prometheus.CounterVec
	cashbackPlansCreated     *prometheus.CounterVec
	cashbackInstallmentsPaid *prometheus.CounterVec
	orderLedgerPostings      *prometheus.CounterVec
	otpRequests              *prometheus.CounterVec
	otpVerifyOutcomes        *prometheus.CounterVec
}

// NewBusinessMetrics registers all business KPI metrics with reg and returns
// the struct. All counters are pre-instantiated at startup (R10).
func NewBusinessMetrics(reg *Registry) *BusinessMetrics {
	m := &BusinessMetrics{
		orderStatusTransitions: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_order_status_transitions_total",
			Help: "Total order status transitions by source and destination status.",
		}, []string{"service", "from", "to"}),

		cashbackPlansCreated: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_cashback_plans_created_total",
			Help: "Total cashback plans created by market.",
		}, []string{"service", "market"}),

		cashbackInstallmentsPaid: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_cashback_installments_paid_total",
			Help: "Total monthly cashback installments paid by market.",
		}, []string{"service", "market"}),

		orderLedgerPostings: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_orderledger_postings_total",
			Help: "Total order-capture ledger postings by service and market.",
		}, []string{"service", "market"}),

		otpRequests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_otp_requests_total",
			Help: "Total OTP requests by service and purpose.",
		}, []string{"service", "purpose"}),

		otpVerifyOutcomes: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_otp_verify_outcomes_total",
			Help: "Total OTP verification attempts by service and outcome.",
		}, []string{"service", "outcome"}),
	}
	reg.MustRegister(
		m.orderStatusTransitions,
		m.cashbackPlansCreated,
		m.cashbackInstallmentsPaid,
		m.orderLedgerPostings,
		m.otpRequests,
		m.otpVerifyOutcomes,
	)
	return m
}

// IncOrderStatusTransition records a single order state machine transition.
// from and to are order status strings (e.g. "pending_payment", "paid").
func (m *BusinessMetrics) IncOrderStatusTransition(svc, from, to string) {
	if m == nil {
		return
	}
	m.orderStatusTransitions.With(prometheus.Labels{
		"service": svc,
		"from":    from,
		"to":      to,
	}).Inc()
}

// IncCashbackPlanCreated increments the plan creation counter for market.
func (m *BusinessMetrics) IncCashbackPlanCreated(svc, market string) {
	if m == nil {
		return
	}
	m.cashbackPlansCreated.With(prometheus.Labels{
		"service": svc,
		"market":  market,
	}).Inc()
}

// IncCashbackInstallmentPaid increments the installment-paid counter for market.
func (m *BusinessMetrics) IncCashbackInstallmentPaid(svc, market string) {
	if m == nil {
		return
	}
	m.cashbackInstallmentsPaid.With(prometheus.Labels{
		"service": svc,
		"market":  market,
	}).Inc()
}

// IncOrderLedgerPosting increments the capture posting counter.
func (m *BusinessMetrics) IncOrderLedgerPosting(svc, market string) {
	if m == nil {
		return
	}
	m.orderLedgerPostings.With(prometheus.Labels{
		"service": svc,
		"market":  market,
	}).Inc()
}

// IncOTPRequest increments the OTP request counter for a given purpose
// (e.g. "login", "stepup").
func (m *BusinessMetrics) IncOTPRequest(svc, purpose string) {
	if m == nil {
		return
	}
	m.otpRequests.With(prometheus.Labels{
		"service": svc,
		"purpose": purpose,
	}).Inc()
}

// IncOTPVerifyOutcome increments the OTP verification counter.
// outcome is one of: "success", "invalid", "expired", "not_found",
// "rate_limited", "deleted", "suspended".
func (m *BusinessMetrics) IncOTPVerifyOutcome(svc, outcome string) {
	if m == nil {
		return
	}
	m.otpVerifyOutcomes.With(prometheus.Labels{
		"service": svc,
		"outcome": outcome,
	}).Inc()
}

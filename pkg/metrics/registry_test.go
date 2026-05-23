package metrics_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/mopro/platform/pkg/metrics"
)

func TestNew_RegistersBuiltins(t *testing.T) {
	reg := metrics.New("test-svc")
	mfs, err := reg.Prometheus().Gather()
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	names := make(map[string]bool, len(mfs))
	for _, mf := range mfs {
		names[mf.GetName()] = true
	}
	// process_cpu_seconds_total is Linux-only; omit from cross-platform test.
	for _, want := range []string{
		"go_goroutines",
		"go_gc_duration_seconds",
		"mopro_build_info",
	} {
		if !names[want] {
			t.Errorf("expected metric %q to be registered; got names: %v", want, nameList(names))
		}
	}
}

func TestNew_NoDuplicateRegistration(t *testing.T) {
	reg := metrics.New("test-svc")
	// Registering the same named metric twice should panic via MustRegister.
	// But a second call to New with a different service creates its own registry
	// with no conflict.
	reg2 := metrics.New("other-svc")
	if reg.Service() == reg2.Service() {
		t.Error("different registries should not share service names in this test")
	}
	// Both should gather without error.
	for _, r := range []*metrics.Registry{reg, reg2} {
		if _, err := r.Prometheus().Gather(); err != nil {
			t.Errorf("Gather: %v", err)
		}
	}
}

func TestAssertCardinalityUnder_Pass(t *testing.T) {
	reg := metrics.New("test-svc")
	// With only built-in metrics, cardinality is well under 10k.
	// Should not panic.
	reg.AssertCardinalityUnder(10_000)
}

func TestAssertCardinalityUnder_Fail(t *testing.T) {
	reg := metrics.New("test-svc")
	defer func() {
		if r := recover(); r == nil {
			t.Error("expected panic when budget exceeded")
		}
	}()
	// Gather returns ~40 metric series for built-ins; budget of 1 must panic.
	reg.AssertCardinalityUnder(1)
}

func TestAllNamedMetricsRegisterWithoutError(t *testing.T) {
	// Each constructor calls MustRegister — a duplicate name or descriptor
	// conflict causes a panic. This test verifies clean registration and that
	// all seeded metrics appear in Gather output.
	reg := metrics.New("test-svc")
	httpM := metrics.NewHTTPMetrics(reg)
	_ = metrics.NewDBMetrics(reg)     // DB/Redis only appear after infra queries
	_ = metrics.NewRedisMetrics(reg)  // same — no infrastructure in unit tests
	ebM := metrics.NewEventBusMetrics(reg)
	outM := metrics.NewOutboxMetrics(reg)
	bizM := metrics.NewBusinessMetrics(reg)

	// Seed HTTP via the actual middleware.
	httpHandler := httpM.Middleware("test-svc", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	req := httptest.NewRequest(http.MethodGet, "/v1/products", nil)
	req.Pattern = "GET /v1/products"
	httpHandler.ServeHTTP(httptest.NewRecorder(), req)

	// Seed eventbus + outbox + business metrics.
	ebM.RecordDispatch("test-svc", "cashback-engine", "ecom.order.delivered.v1", "success", 0)
	ebM.RecordDLQ("test-svc", "cashback-engine", "ecom.order.delivered.v1")
	outM.RecordPublish("test-svc", "ecom.order.paid.v1", "ok")
	outM.SetLag("test-svc", 0)
	bizM.IncCashbackPlanCreated("test-svc", "TR")
	bizM.IncCashbackInstallmentPaid("test-svc", "TR")
	bizM.IncOrderLedgerPosting("test-svc", "TR")
	bizM.IncOrderStatusTransition("test-svc", "pending_payment", "paid")
	bizM.IncOTPRequest("test-svc", "login")
	bizM.IncOTPVerifyOutcome("test-svc", "success")

	mfs, err := reg.Prometheus().Gather()
	if err != nil {
		t.Fatalf("Gather after seeding all metrics: %v", err)
	}
	names := make(map[string]bool, len(mfs))
	for _, mf := range mfs {
		names[mf.GetName()] = true
	}
	// DB/Redis histograms are excluded: they require live infrastructure.
	wantSeeded := []string{
		"mopro_build_info",
		"mopro_http_requests_total",
		"mopro_http_request_duration_seconds",
		"mopro_eventbus_messages_processed_total",
		"mopro_eventbus_dlq_messages_total",
		"mopro_outbox_published_total",
		"mopro_outbox_lag_seconds",
		"mopro_order_status_transitions_total",
		"mopro_cashback_plans_created_total",
		"mopro_cashback_installments_paid_total",
		"mopro_orderledger_postings_total",
		"mopro_otp_requests_total",
		"mopro_otp_verify_outcomes_total",
	}
	for _, n := range wantSeeded {
		if !names[n] {
			t.Errorf("expected metric %q in Gather output after seeding", n)
		}
	}
}

func TestNoPIIInMetricNames(t *testing.T) {
	reg := metrics.New("test-svc")
	_ = metrics.NewHTTPMetrics(reg)
	_ = metrics.NewDBMetrics(reg)
	_ = metrics.NewRedisMetrics(reg)
	_ = metrics.NewEventBusMetrics(reg)
	_ = metrics.NewOutboxMetrics(reg)
	_ = metrics.NewBusinessMetrics(reg)

	mfs, _ := reg.Prometheus().Gather()
	banned := []string{"user_id", "email", "phone", "card", "payment_id", "order_id", "plan_id"}
	for _, mf := range mfs {
		for _, ban := range banned {
			if strings.Contains(mf.GetName(), ban) {
				t.Errorf("PII label pattern %q found in metric name %q", ban, mf.GetName())
			}
		}
		for _, metric := range mf.GetMetric() {
			for _, lp := range metric.GetLabel() {
				if strings.Contains(lp.GetName(), "user_id") ||
					strings.Contains(lp.GetName(), "email") ||
					strings.Contains(lp.GetName(), "phone") {
					t.Errorf("PII label %q found in metric %q", lp.GetName(), mf.GetName())
				}
			}
		}
	}
}

func nameList(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

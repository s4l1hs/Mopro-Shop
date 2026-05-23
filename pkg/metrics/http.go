package metrics

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// HTTPMetrics holds the HTTP request counter and latency histogram registered
// at startup. Pass the *Registry from New() and nil-check is never needed —
// all methods are safe to call concurrently after construction.
type HTTPMetrics struct {
	requests *prometheus.CounterVec
	latency  *prometheus.HistogramVec
}

// NewHTTPMetrics registers HTTP request metrics with reg and returns the struct.
// Buckets follow D5: 5ms–10s for request latency.
func NewHTTPMetrics(reg *Registry) *HTTPMetrics {
	m := &HTTPMetrics{
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_http_requests_total",
			Help: "Total HTTP requests partitioned by service, method, route template, and status code.",
		}, []string{"service", "method", "route", "status"}),

		latency: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "mopro_http_request_duration_seconds",
			Help:    "HTTP request latency in seconds partitioned by service, method, route, and status.",
			Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
		}, []string{"service", "method", "route", "status"}),
	}
	reg.MustRegister(m.requests, m.latency)
	return m
}

// Middleware returns an http.Handler that records request count and latency for
// every request passing through it. Must be called once per handler at startup
// (not per-request) to avoid label cardinality explosions.
//
// Route is taken from r.Pattern (Go 1.22+ stdlib mux route template, e.g.
// "GET /v1/orders/{id}"). Falls back to r.URL.Path when Pattern is empty.
// Using the template avoids a new label series for every unique order ID.
func (m *HTTPMetrics) Middleware(svc string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		route := r.Pattern
		if route == "" {
			route = r.URL.Path
		}
		rw := &statusCapture{ResponseWriter: w, code: http.StatusOK}
		start := time.Now()
		defer func() {
			dur := time.Since(start).Seconds()
			status := strconv.Itoa(rw.code)
			m.requests.With(prometheus.Labels{
				"service": svc,
				"method":  r.Method,
				"route":   route,
				"status":  status,
			}).Inc()
			m.latency.With(prometheus.Labels{
				"service": svc,
				"method":  r.Method,
				"route":   route,
				"status":  status,
			}).Observe(dur)
		}()
		next.ServeHTTP(rw, r)
	})
}

// statusCapture wraps http.ResponseWriter to capture the response status code.
// Distinct from otelx.statusWriter to avoid an import cycle.
type statusCapture struct {
	http.ResponseWriter
	code    int
	written bool
}

func (s *statusCapture) WriteHeader(code int) {
	if !s.written {
		s.code = code
		s.written = true
	}
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusCapture) Write(b []byte) (int, error) {
	if !s.written {
		s.written = true
	}
	return s.ResponseWriter.Write(b)
}

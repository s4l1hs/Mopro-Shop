package sipay

import (
	"github.com/mopro/platform/pkg/metrics"
	"github.com/prometheus/client_golang/prometheus"
)

// SipayMetrics holds per-request Prometheus metrics for all Sipay API calls.
// Pass nil to NewAdapter when metrics are not wired (e.g. in tests).
type SipayMetrics struct {
	requestDuration *prometheus.HistogramVec
	requestTotal    *prometheus.CounterVec
	cbOpen          prometheus.Gauge
}

// NewSipayMetrics registers Sipay metrics with reg and returns the handle.
// Call once at startup and pass to NewAdapter via WithMetrics.
func NewSipayMetrics(reg *metrics.Registry) *SipayMetrics {
	duration := prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "sipay_request_duration_seconds",
		Help:    "Sipay API call latency in seconds, by endpoint and HTTP/application status.",
		Buckets: prometheus.DefBuckets,
	}, []string{"endpoint", "status"})

	total := prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "sipay_request_total",
		Help: "Total Sipay API calls, by endpoint and HTTP/application status.",
	}, []string{"endpoint", "status"})

	cbOpen := prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "sipay_circuit_breaker_open",
		Help: "1 when the Sipay circuit breaker is open (requests are being rejected), 0 when closed.",
	})

	reg.MustRegister(duration, total, cbOpen)
	return &SipayMetrics{
		requestDuration: duration,
		requestTotal:    total,
		cbOpen:          cbOpen,
	}
}

func (m *SipayMetrics) observe(endpoint, status string, durSec float64) {
	if m == nil {
		return
	}
	m.requestDuration.WithLabelValues(endpoint, status).Observe(durSec)
	m.requestTotal.WithLabelValues(endpoint, status).Inc()
}

func (m *SipayMetrics) setCBOpen(open bool) {
	if m == nil {
		return
	}
	v := float64(0)
	if open {
		v = 1
	}
	m.cbOpen.Set(v)
}

// Package metrics provides a Prometheus-based metrics registry and helpers for
// Mopro services. Uses github.com/prometheus/client_golang — NOT OpenTelemetry
// Metrics SDK. OTel SDK is used only for distributed tracing (pkg/otelx).
package metrics

import (
	"fmt"
	"runtime"
	"runtime/debug"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
)

// Registry wraps a prometheus.Registry with factory helpers and a service name.
type Registry struct {
	reg     *prometheus.Registry
	service string
}

// New creates a per-service Registry. Registers Go runtime, process, and
// build_info collectors automatically. ProcessCollector registration is best-
// effort (not available on all platforms/OS combinations).
func New(service string) *Registry {
	r := &Registry{
		reg:     prometheus.NewRegistry(),
		service: service,
	}
	r.reg.MustRegister(
		collectors.NewGoCollector(),
		newBuildInfoCollector(service),
	)
	// ProcessCollector may fail on non-Linux platforms (macOS, Windows).
	// Register best-effort: log nothing, skip silently.
	_ = r.reg.Register(collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))
	return r
}

// MustRegister panics if any collector fails to register.
// Only called at startup — never in hot paths.
func (r *Registry) MustRegister(cs ...prometheus.Collector) {
	r.reg.MustRegister(cs...)
}

// Prometheus returns the underlying prometheus.Registry for use with promhttp.
func (r *Registry) Prometheus() *prometheus.Registry {
	return r.reg
}

// Service returns the service name this registry was created for.
func (r *Registry) Service() string {
	return r.service
}

// AssertCardinalityUnder panics if the instantiated label combinations across all
// registered metric families exceed budget. Call after all metrics are registered
// and seed data has been observed (e.g. at the end of main init).
// A budget of 10_000 covers the full Mopro metric set with room to grow.
func (r *Registry) AssertCardinalityUnder(budget int) {
	mfs, err := r.reg.Gather()
	if err != nil {
		panic(fmt.Sprintf("metrics: Gather failed during cardinality check: %v", err))
	}
	total := 0
	for _, mf := range mfs {
		total += len(mf.GetMetric())
	}
	if total > budget {
		panic(fmt.Sprintf(
			"metrics: cardinality budget exceeded — %d active series > budget %d. "+
				"Remove high-cardinality labels (user_id, order_id, etc.)",
			total, budget,
		))
	}
}

// newBuildInfoCollector returns a gauge metric that is always 1 and carries
// build metadata: service name, VCS commit, Go version, and build timestamp.
// Dashboard panels use this to correlate anomalies with deployments.
func newBuildInfoCollector(service string) prometheus.Collector {
	goVersion := runtime.Version()
	version := "unknown"
	buildTime := "unknown"
	if bi, ok := debug.ReadBuildInfo(); ok {
		if bi.Main.Version != "" && bi.Main.Version != "(devel)" {
			version = bi.Main.Version
		}
		for _, s := range bi.Settings {
			switch s.Key {
			case "vcs.revision":
				if s.Value != "" {
					version = s.Value[:min(len(s.Value), 12)] // short SHA
				}
			case "vcs.time":
				buildTime = s.Value
			}
		}
	}
	g := prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "mopro_build_info",
		Help: "Build metadata. Value is always 1. Use for deployment correlation.",
	}, []string{"service", "version", "goversion", "buildtime"})
	g.With(prometheus.Labels{
		"service":   service,
		"version":   version,
		"goversion": goVersion,
		"buildtime": buildTime,
	}).Set(1)
	return g
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

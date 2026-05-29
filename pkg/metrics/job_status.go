package metrics

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// JobStatusMetrics exposes a last-run status gauge and timestamp gauge for
// scheduled cron jobs. Wire one shared instance into all fin-svc crona so
// Grafana/Mimir can alert when a job fails or stops running.
//
// Gauge semantics:
//
//	mopro_job_last_run_status{service,job}      1 = last run succeeded, 0 = failed
//	mopro_job_last_run_timestamp_seconds{service,job}  Unix epoch of last completion
type JobStatusMetrics struct {
	status    *prometheus.GaugeVec
	timestamp *prometheus.GaugeVec
}

// NewJobStatusMetrics registers job status gauges with reg and returns the handle.
func NewJobStatusMetrics(reg *Registry) *JobStatusMetrics {
	m := &JobStatusMetrics{
		status: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "mopro_job_last_run_status",
			Help: "Status of the most recent job run: 1=success, 0=failure. Never set = job has not run since startup.",
		}, []string{"service", "job"}),

		timestamp: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "mopro_job_last_run_timestamp_seconds",
			Help: "Unix timestamp of the most recent job run completion (success or failure).",
		}, []string{"service", "job"}),
	}
	reg.MustRegister(m.status, m.timestamp)
	return m
}

// SetSuccess records a successful job run.
func (m *JobStatusMetrics) SetSuccess(svc, job string) {
	if m == nil {
		return
	}
	labels := prometheus.Labels{"service": svc, "job": job}
	m.status.With(labels).Set(1)
	m.timestamp.With(labels).Set(float64(time.Now().Unix()))
}

// SetFailure records a failed job run.
func (m *JobStatusMetrics) SetFailure(svc, job string) {
	if m == nil {
		return
	}
	labels := prometheus.Labels{"service": svc, "job": job}
	m.status.With(labels).Set(0)
	m.timestamp.With(labels).Set(float64(time.Now().Unix()))
}

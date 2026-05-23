package metrics

import (
	"context"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
)

// DBMetrics holds the query duration histogram for pgx connections.
type DBMetrics struct {
	queryDuration *prometheus.HistogramVec
}

// NewDBMetrics registers DB query metrics with reg and returns the struct.
// Buckets follow D5: 1ms–5s for DB query latency.
func NewDBMetrics(reg *Registry) *DBMetrics {
	m := &DBMetrics{
		queryDuration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "mopro_db_query_duration_seconds",
			Help:    "PostgreSQL query latency in seconds partitioned by service and operation type.",
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		}, []string{"service", "op"}),
	}
	reg.MustRegister(m.queryDuration)
	return m
}

// Tracer returns a pgx.QueryTracer that records per-query latency.
// Add it to pgxpool.Config.ConnConfig.Tracer before creating the pool.
//
// Only the operation type (SELECT/INSERT/UPDATE/DELETE/OTHER) is recorded as a
// label — never the SQL text (would be high-cardinality and may contain PII).
func (m *DBMetrics) Tracer(svc string) pgx.QueryTracer {
	return &pgxTracer{m: m, svc: svc}
}

// WirePool adds the tracer to an existing pgxpool.Config.
// Call before pgxpool.NewWithConfig.
func (m *DBMetrics) WirePool(cfg *pgxpool.Config, svc string) {
	cfg.ConnConfig.Tracer = m.Tracer(svc)
}

type traceKey struct{}

// pgxTracer implements pgx.QueryTracer.
type pgxTracer struct {
	m   *DBMetrics
	svc string
}

type traceData struct {
	start time.Time
	op    string
}

func (t *pgxTracer) TraceQueryStart(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryStartData) context.Context {
	return context.WithValue(ctx, traceKey{}, traceData{
		start: time.Now(),
		op:    sqlOp(data.SQL),
	})
}

func (t *pgxTracer) TraceQueryEnd(ctx context.Context, _ *pgx.Conn, _ pgx.TraceQueryEndData) {
	v, ok := ctx.Value(traceKey{}).(traceData)
	if !ok {
		return
	}
	t.m.queryDuration.With(prometheus.Labels{
		"service": t.svc,
		"op":      v.op,
	}).Observe(time.Since(v.start).Seconds())
}

// sqlOp extracts the DML operation type from the first word of the SQL statement.
// Never logs the full SQL to avoid PII exposure.
func sqlOp(sql string) string {
	s := strings.TrimSpace(sql)
	idx := strings.IndexAny(s, " \t\n(")
	if idx > 0 {
		s = s[:idx]
	}
	switch strings.ToUpper(s) {
	case "SELECT":
		return "SELECT"
	case "INSERT":
		return "INSERT"
	case "UPDATE":
		return "UPDATE"
	case "DELETE":
		return "DELETE"
	case "CALL":
		return "CALL"
	default:
		return "OTHER"
	}
}

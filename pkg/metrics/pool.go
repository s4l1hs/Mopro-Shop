package metrics

import (
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
)

// pgxPoolCollector is a prometheus.Collector that reads live stats from a
// pgxpool.Pool on every Collect call. Register once at startup.
type pgxPoolCollector struct {
	pool    *pgxpool.Pool
	svc     string
	db      string
	acquired *prometheus.Desc
	idle     *prometheus.Desc
	maxConns *prometheus.Desc
	total    *prometheus.Desc
}

// RegisterPgxPoolCollector wires a pgxpool.Pool into the Prometheus registry so
// connection pool saturation is visible in Grafana. Safe to call with the same
// pool multiple times only when svc+db differ.
func RegisterPgxPoolCollector(reg *Registry, pool *pgxpool.Pool, svc, db string) {
	labels := prometheus.Labels{"service": svc, "db": db}
	c := &pgxPoolCollector{
		pool: pool,
		svc:  svc,
		db:   db,
		acquired: prometheus.NewDesc(
			"mopro_pgx_pool_acquired_conns",
			"Number of connections currently acquired (in use) from the pool.",
			nil, labels,
		),
		idle: prometheus.NewDesc(
			"mopro_pgx_pool_idle_conns",
			"Number of idle connections in the pool.",
			nil, labels,
		),
		maxConns: prometheus.NewDesc(
			"mopro_pgx_pool_max_conns",
			"Maximum number of connections allowed in the pool.",
			nil, labels,
		),
		total: prometheus.NewDesc(
			"mopro_pgx_pool_total_conns",
			"Total number of connections (acquired + idle + constructing) in the pool.",
			nil, labels,
		),
	}
	reg.MustRegister(c)
}

func (c *pgxPoolCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.acquired
	ch <- c.idle
	ch <- c.maxConns
	ch <- c.total
}

func (c *pgxPoolCollector) Collect(ch chan<- prometheus.Metric) {
	stat := c.pool.Stat()
	ch <- prometheus.MustNewConstMetric(c.acquired, prometheus.GaugeValue, float64(stat.AcquiredConns()))
	ch <- prometheus.MustNewConstMetric(c.idle, prometheus.GaugeValue, float64(stat.IdleConns()))
	ch <- prometheus.MustNewConstMetric(c.maxConns, prometheus.GaugeValue, float64(stat.MaxConns()))
	ch <- prometheus.MustNewConstMetric(c.total, prometheus.GaugeValue, float64(stat.TotalConns()))
}

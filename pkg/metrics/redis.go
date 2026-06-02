package metrics

import (
	"context"
	"net"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/redis/go-redis/v9"
)

// RedisMetrics holds the Redis command duration histogram.
type RedisMetrics struct {
	cmdDuration *prometheus.HistogramVec
}

// NewRedisMetrics registers Redis command metrics with reg.
// Buckets follow D5: 100µs–500ms for Redis command latency.
func NewRedisMetrics(reg *Registry) *RedisMetrics {
	m := &RedisMetrics{
		cmdDuration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "mopro_redis_command_duration_seconds",
			Help:    "Redis command latency in seconds partitioned by service and command name.",
			Buckets: []float64{0.0001, 0.0005, 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5},
		}, []string{"service", "cmd"}),
	}
	reg.MustRegister(m.cmdDuration)
	return m
}

// Hook returns a redis.Hook that records per-command latency.
// Wire with client.AddHook(m.Hook(svc)) after constructing the client.
func (m *RedisMetrics) Hook(svc string) redis.Hook {
	return &redisHook{m: m, svc: svc}
}

type redisHook struct {
	m   *RedisMetrics
	svc string
}

func (h *redisHook) DialHook(next redis.DialHook) redis.DialHook {
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		return next(ctx, network, addr)
	}
}

func (h *redisHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		start := time.Now()
		err := next(ctx, cmd)
		h.m.cmdDuration.With(prometheus.Labels{
			"service": h.svc,
			"cmd":     cmd.Name(),
		}).Observe(time.Since(start).Seconds())
		return err
	}
}

func (h *redisHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, cmds []redis.Cmder) error {
		start := time.Now()
		err := next(ctx, cmds)
		// Record the pipeline as a single "pipeline" command with count=len(cmds).
		h.m.cmdDuration.With(prometheus.Labels{
			"service": h.svc,
			"cmd":     "pipeline",
		}).Observe(time.Since(start).Seconds())
		return err
	}
}

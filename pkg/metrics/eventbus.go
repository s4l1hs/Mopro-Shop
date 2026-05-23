package metrics

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// EventBusMetrics tracks event consumer throughput and DLQ activity.
// Wire into RedisBus via eventbus.WithMetrics in main.go.
type EventBusMetrics struct {
	processed   *prometheus.CounterVec
	processDur  *prometheus.HistogramVec
	dlqMessages *prometheus.CounterVec
}

// NewEventBusMetrics registers event bus metrics with reg.
func NewEventBusMetrics(reg *Registry) *EventBusMetrics {
	m := &EventBusMetrics{
		processed: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_eventbus_messages_processed_total",
			Help: "Total event bus messages processed by consumer group, event type, and outcome.",
		}, []string{"service", "consumer", "event_type", "outcome"}),

		processDur: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "mopro_eventbus_message_duration_seconds",
			Help:    "Event handler execution time in seconds.",
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		}, []string{"service", "consumer", "event_type"}),

		dlqMessages: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_eventbus_dlq_messages_total",
			Help: "Total messages moved to the dead-letter queue by consumer and event type.",
		}, []string{"service", "consumer", "event_type"}),
	}
	reg.MustRegister(m.processed, m.processDur, m.dlqMessages)
	return m
}

// RecordDispatch records the outcome and duration of a single message dispatch.
// outcome must be "success", "error", or "panic".
func (m *EventBusMetrics) RecordDispatch(svc, consumer, eventType, outcome string, dur time.Duration) {
	m.processed.With(prometheus.Labels{
		"service":    svc,
		"consumer":   consumer,
		"event_type": eventType,
		"outcome":    outcome,
	}).Inc()
	m.processDur.With(prometheus.Labels{
		"service":    svc,
		"consumer":   consumer,
		"event_type": eventType,
	}).Observe(dur.Seconds())
}

// RecordDLQ increments the DLQ counter when a message is moved to the dead-letter queue.
func (m *EventBusMetrics) RecordDLQ(svc, consumer, eventType string) {
	m.dlqMessages.With(prometheus.Labels{
		"service":    svc,
		"consumer":   consumer,
		"event_type": eventType,
	}).Inc()
}

// OutboxMetrics tracks outbox publisher throughput.
type OutboxMetrics struct {
	published *prometheus.CounterVec
	batchDur  *prometheus.HistogramVec
	lagGauge  *prometheus.GaugeVec
}

// NewOutboxMetrics registers outbox publisher metrics with reg.
func NewOutboxMetrics(reg *Registry) *OutboxMetrics {
	m := &OutboxMetrics{
		published: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "mopro_outbox_published_total",
			Help: "Total outbox events published to Redis Streams by service, event type, and result.",
		}, []string{"service", "event_type", "result"}),

		batchDur: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "mopro_outbox_batch_duration_seconds",
			Help:    "Outbox drain batch duration in seconds.",
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		}, []string{"service"}),

		lagGauge: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "mopro_outbox_lag_seconds",
			Help: "Age in seconds of the oldest unpublished outbox row (0 when queue is empty).",
		}, []string{"service"}),
	}
	reg.MustRegister(m.published, m.batchDur, m.lagGauge)
	return m
}

// RecordPublish increments the published counter for a single outbox row.
// result is "ok" or "error".
func (m *OutboxMetrics) RecordPublish(svc, eventType, result string) {
	m.published.With(prometheus.Labels{
		"service":    svc,
		"event_type": eventType,
		"result":     result,
	}).Inc()
}

// RecordBatch records the duration of one drain batch cycle.
func (m *OutboxMetrics) RecordBatch(svc string, dur time.Duration) {
	m.batchDur.With(prometheus.Labels{"service": svc}).Observe(dur.Seconds())
}

// SetLag records the outbox publisher lag gauge.
func (m *OutboxMetrics) SetLag(svc string, lagSeconds float64) {
	m.lagGauge.With(prometheus.Labels{"service": svc}).Set(lagSeconds)
}
